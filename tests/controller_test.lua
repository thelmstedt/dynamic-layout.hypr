local a = require("tests.support.assertions")
local fixture = require("tests.support.fixtures")

local function engine()
  local env = fixture.engine()
  -- Emulate dispatch to the registered provider. This checks that controller
  -- callbacks reach the same state transitions as Hyprland layout messages.
  hl.dispatch = function(message)
    env.dispatched[#env.dispatched + 1] = message
    if type(message) == "string" then
      a.equal(env.controller.definition.layout_msg(env.context, message), true)
    end
  end
  return env
end

return {
  ["directional focus follows swap neighbors without reordering"] = function()
    local env = engine()
    local layout = env.controller
    for _, name in ipairs({ "fullscreen", "tall", "wide", "three_col" }) do
      layout.definition.layout_msg(env.context, name)
      for _, reflected in ipairs({ false, true }) do
        env.ws.reflect = reflected
        for index = 1, 3 do
          fixture.focus(env, index)
          for _, direction in ipairs({ "l", "r", "u", "d" }) do
            local before = #env.dispatched
            layout.move_direction(direction)
            local focus = env.dispatched[before + 1]
            layout.swap_direction(direction)
            local destination
            for slot, id in ipairs(env.ws.order) do
              if id == tostring(index) and slot ~= index then destination = slot end
            end
            if destination then
              a.equal(focus.window, "address:window" .. destination)
            else
              a.equal(focus, nil)
            end
            -- Undo the swap to check each direction from the same order.
            if destination then
              env.ws.order[index], env.ws.order[destination] = env.ws.order[destination], env.ws.order[index]
            end
          end
        end
      end
    end
  end,

  ["directional focus falls back outside managed tiled windows"] = function()
    local env = engine()
    env.controller.move_direction("l")
    a.equal(env.dispatched[#env.dispatched].direction, "l")
    fixture.focus(env, 1)
    env.active_window.floating = true
    env.controller.move_direction("r")
    a.equal(env.dispatched[#env.dispatched].direction, "r")
    env.active_window.floating = false
    env.active_window.layout.name = "other"
    env.controller.move_direction("u")
    a.equal(env.dispatched[#env.dispatched].direction, "u")
  end,

  ["resize and reset callbacks operate on workspace settings"] = function()
    local env = engine()
    local layout = env.controller
    layout.next_layout()
    a.equal(env.ws.active_layout.name, "tall")
    fixture.focus(env, 1)
    layout.grow()
    a.near(env.ws.layout_state.tall.ratio, 0.53)
    layout.shrink()
    a.near(env.ws.layout_state.tall.ratio, 0.5)
    layout.set_ratio(0.7)
    a.near(env.ws.layout_state.tall.ratio, 0.7)
    layout.reflect()
    a.equal(env.ws.reflect, true)
    layout.reset()
    a.equal(env.ws.reflect, false)
    a.near(env.ws.layout_state.tall.ratio, 0.5)
    a.equal(env.ws.active_layout.name, "tall")
    layout.prev_layout()
    a.equal(env.ws.active_layout.name, "fullscreen")
  end,

  ["reordering callbacks preserve distinct swap promote and demote behavior"] = function()
    local env = engine()
    local layout = env.controller
    fixture.focus(env, 3)
    layout.swap_with_master()
    a.equal(table.concat(env.ws.order, ","), "3,2,1")
    layout.demote()
    a.equal(table.concat(env.ws.order, ","), "2,1,3")
    layout.promote()
    a.equal(table.concat(env.ws.order, ","), "3,2,1")
    layout.swap_active(true)
    a.equal(table.concat(env.ws.order, ","), "2,3,1")
    layout.swap_direction("r")
    a.equal(table.concat(env.ws.order, ","), "2,1,3")
  end,

  ["callbacks dispatch without an active window on empty workspaces"] = function()
    local env = engine()
    env.context = env.empty
    env.active_window = nil
    env.ws.reflect = true
    env.ws.layout_state.wide.ratio = 0.8
    env.controller.reset()
    a.equal(env.ws.reflect, false)
    a.near(env.ws.layout_state.wide.ratio, 0.5)
    env.controller.reflect()
    a.equal(env.ws.reflect, true)
    env.controller.next_layout()
    a.equal(env.ws.active_layout.name, "tall")
  end,

  ["invalid ratios fail before dispatch"] = function()
    local env = engine()
    local before = #env.dispatched
    for _, ratio in ipairs({ 0, 1, math.huge, 0 / 0 }) do
      a.equal(pcall(env.controller.set_ratio, ratio), false)
    end
    a.equal(#env.dispatched, before)
  end,
}
