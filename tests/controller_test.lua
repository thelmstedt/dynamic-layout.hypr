local a = require("tests.support.assertions")
local fixture = require("tests.support.fixtures")

local function engine(window_count)
  local env = fixture.engine(window_count)
  -- Refresh is the only layout message emitted by controller operations.
  hl.dispatch = function(message)
    env.dispatched[#env.dispatched + 1] = message
    if message.kind == "layout" then
      a.dispatch(message, "layout", "_refresh")
      a.equal(env.registered.dynamic.layout_msg(env.context, message.options), true)
    end
  end
  return env
end

return {
  ["controller changes are published before requesting refresh"] = function()
    local env = fixture.engine()
    env.registered.dynamic.layout_msg(env.context, "tall")
    fixture.focus(env, 1)
    local refreshes = 0
    hl.dispatch = function(message)
      a.dispatch(message, "layout", "_refresh")
      refreshes = refreshes + 1
      a.near(env.ws.layout_state.tall.ratio, 0.47)
      assert(a.read(env.state_path):find("TALL@0.470", 1, true))
      -- No operation needs to run through layout_msg for the change to exist.
    end
    env.controller.shrink()
    a.equal(refreshes, 1)
  end,

  ["refresh and recalculation preserve direct window reordering"] = function()
    local env = engine()
    fixture.focus(env, 3)
    env.controller.promote()
    a.equal(table.concat(env.ws.order, ","), "3,1,2")
    env.registered.dynamic.recalculate(env.context)
    a.equal(table.concat(env.ws.order, ","), "3,1,2")
    a.box(env.boxes[3], { x = 0, y = 0, w = 100, h = 100 })
  end,

  ["controller creates state for an empty focused workspace"] = function()
    local env = fixture.engine()
    env.focused_workspace = { id = 99 }
    env.active_window = nil
    env.controller.shrink()
    local ws = env.store.workspaces["id:99"]
    a.near(ws.layout_state.tall.ratio, 0.47)
    a.equal(env.ws.active_layout.name, "fullscreen")
    a.dispatch(env.dispatched[#env.dispatched], "layout", "_refresh")
  end,

  ["three-column row survives resizing and reflection while reset restores the first row"] = function()
    for _, command in ipairs({ "grow", "shrink", "ratio 0.6", "reflect", "reset", "swapnext" }) do
      local env = fixture.engine(5)
      local layout = env.controller
      env.registered.dynamic.layout_msg(env.context, "three_col")
      fixture.focus(env, 4)
      layout.move_direction("r")
      fixture.focus(env, 1)
      if command == "ratio 0.6" then layout.set_ratio(0.6)
      elseif command == "swapnext" then layout.swap_next()
      else layout[command]() end
      layout.move_direction("r")
      local expected = ({ reflect = 4, reset = 3, swapnext = 2 })[command] or 5
      a.dispatch(env.dispatched[#env.dispatched], "focus", { window = "address:window" .. expected })
    end
  end,

  ["three-column focus preserves rows through the master in both directions"] = function()
    for _, reflected in ipairs({ false, true }) do
      local env = fixture.engine(5)
      env.registered.dynamic.layout_msg(env.context, "three_col")
      env.ws.reflect = reflected
      local function move(direction, expected)
        env.controller.move_direction(direction)
        a.dispatch(env.dispatched[#env.dispatched], "focus", { window = "address:window" .. expected })
        fixture.focus(env, expected)
        a.equal(table.concat(env.ws.order, ","), "1,2,3,4,5")
      end
      local right, left = reflected and "l" or "r", reflected and "r" or "l"
      for _, row in ipairs({ { 2, 3 }, { 4, 5 } }) do
        fixture.focus(env, row[1])
        move(right, 1)
        move(right, row[2])
        move(left, 1)
        move(left, row[1])
        move(right, 1)
        move(left, row[1])
      end
      move(right, 1)
      fixture.focus(env, 2)
      fixture.focus(env, 1)
      move(right, 3)
      -- Mouse/external focus on a lower side window establishes the row too.
      fixture.focus(env, 4)
      fixture.focus(env, 1)
      move(right, 5)
    end
  end,

  ["directional focus follows swap neighbors without reordering"] = function()
    local env = engine()
    local layout = env.controller
    for _, name in ipairs({ "fullscreen", "tall", "wide", "three_col" }) do
      env.registered.dynamic.layout_msg(env.context, name)
      for _, reflected in ipairs({ false, true }) do
        env.ws.reflect = reflected
        for index = 1, 3 do
          fixture.focus(env, index)
          for _, direction in ipairs({ "l", "r", "u", "d" }) do
            local before = #env.dispatched
            layout.move_direction(direction)
            local focus = env.dispatched[before + 1]
            a.equal(table.concat(env.ws.order, ","), "1,2,3")
            layout.swap_direction(direction)
            local destination
            for slot, id in ipairs(env.ws.order) do
              if id == tostring(index) and slot ~= index then destination = slot end
            end
            if destination then
              a.dispatch(focus, "focus", { window = "address:window" .. destination })
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
    a.dispatch(env.dispatched[#env.dispatched], "focus", { direction = "l" })
    fixture.focus(env, 1)
    env.active_window.floating = true
    env.controller.move_direction("r")
    a.dispatch(env.dispatched[#env.dispatched], "focus", { direction = "r" })
    env.active_window.floating = false
    env.active_window.layout.name = "other"
    env.controller.move_direction("u")
    a.dispatch(env.dispatched[#env.dispatched], "focus", { direction = "u" })
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
    local env = engine(0)
    a.equal(#env.windows, 0)
    a.equal(#env.ws.order, 0)
    a.equal(env.active_window, nil)
    env.ws.reflect = true
    env.ws.layout_state.tall.ratio = 0.8
    env.ws.layout_state.wide.ratio = 0.8
    env.controller.reset()
    a.equal(env.ws.active_layout.name, "fullscreen")
    a.near(env.ws.layout_state.tall.ratio, 0.5)
    a.equal(env.ws.reflect, false)
    a.near(env.ws.layout_state.wide.ratio, 0.5)
    env.controller.reflect()
    a.equal(env.ws.reflect, true)
    env.controller.next_layout()
    a.equal(env.ws.active_layout.name, "tall")
    a.equal(#env.dispatched, 3)
    for _, message in ipairs(env.dispatched) do
      a.dispatch(message, "layout", "_refresh")
    end
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
