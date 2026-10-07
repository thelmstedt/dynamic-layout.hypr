local a = require("tests.support.assertions")
local json = require("dynamic_layout.vendor.json")
local fixture = require("tests.support.fixtures")
local util = require("dynamic_layout.framework.util")

-- A minimal custom strategy (equal-height rows) for exercising setup with a
-- user-supplied strategy table. Fresh each call so a test can mutate it freely.
local function rows_strategy()
  return {
    name = "rows",
    reflect_axis = "y",
    new_state = function() return {} end,
    geometry = function(_, context, workspace)
      return util.stack_boxes(context, workspace.order, context.area, "vertical")
    end,
  }
end

return {
  ["custom strategies run through setup and survive list changes"] = function()
    local env = fixture.engine(3)
    local original_getenv = os.getenv
    local state_root = fixture.path("custom")
    ---@diagnostic disable-next-line: duplicate-set-field
    os.getenv = function(name)
      if name == "XDG_STATE_HOME" then return state_root end
      return original_getenv(name)
    end
    local rows = rows_strategy()
    local tall = require("dynamic_layout.strategies.tall")("tall")
    local layout = require("dynamic_layout").setup({ strategies = { rows, tall }, resize_delta = 0.07 })
    function env.context:split(area, side, ratio)
      return { x = area.x, y = area.y + (side == "bottom" and area.h * (1 - ratio) or 0),
        w = area.w, h = area.h * ratio }
    end
    local path = state_root .. "/dynamic-layout.hypr/state.json"
    local function workspace()
      return json.decode(a.read(path)).workspaces["id:10"]
    end
    env.registered.dynamic.recalculate(env.context)
    a.equal(workspace().active_layout, "rows")
    a.near(env.boxes[1].h, 100 / 3)
    a.near(env.boxes[3].y, 200 / 3)
    fixture.focus(env, 2)
    layout.focus_direction("d")
    a.dispatch(env.dispatched[#env.dispatched], "focus", { window = "address:window3" })
    layout.reflect()
    env.registered.dynamic.recalculate(env.context)
    a.near(env.boxes[1].y, 200 / 3)
    layout.next_layout()
    a.equal(workspace().active_layout, "tall")
    layout.set_ratio(0.63)
    layout.grow()
    a.near(workspace().layout_state.tall.ratio, 0.70)
    layout.shrink()
    layout.prev_layout()
    a.equal(workspace().active_layout, "rows")

    require("dynamic_layout").setup({ strategies = { tall, require("dynamic_layout.strategies.fullscreen")("fullscreen") } })
    local saved = workspace()
    a.equal(saved.active_layout, "tall")
    a.near(saved.layout_state.tall.ratio, 0.63)
    a.equal(saved.layout_state.rows, nil)
    a.equal(type(saved.layout_state.fullscreen), "table")
    a.equal(saved.reflect, true)
    a.equal(#saved.order, 3)
  end,

  ["reserved strategy names fail at registration"] = function()
    local rows = rows_strategy()
    rows.name = "_refresh"
    local ok, err = pcall(require("dynamic_layout").setup, { strategies = { rows } })
    a.equal(ok, false)
    assert(tostring(err):find("strategy name is reserved", 1, true))
  end,

  ["import has no registration side effects"] = function()
    local env = fixture.hyprland()
    -- Execute the module freshly even when another case already required it.
    local module = dofile("lua/dynamic_layout.lua")
    a.equal(type(module.setup), "function")
    a.equal(next(env.registered), nil)
    a.equal(next(env.hooks), nil)
  end,

  ["default paths work when Hyprland has reaped the mkdir child"] = function()
    local env = fixture.hyprland()
    local original_getenv = os.getenv
    local state_root = fixture.path("state")
    ---@diagnostic disable-next-line: duplicate-set-field
    os.getenv = function(name)
      if name == "XDG_STATE_HOME" then return state_root end
      assert(name ~= "XDG_RUNTIME_DIR", "paths should only depend on XDG_STATE_HOME")
      return original_getenv(name)
    end
    local execute = os.execute
    ---@diagnostic disable-next-line: duplicate-set-field
    os.execute = function(command)
      assert(execute(command))
      return nil, "No child processes", 10
    end
    local controller = require("dynamic_layout").setup()
    a.equal(controller.name, "dynamic")
    a.equal(type(env.registered.dynamic.recalculate), "function")
    a.equal(type(env.registered.dynamic.layout_msg), "function")
    for _, field in ipairs({ "store", "definition", "publish" }) do
      a.equal(controller[field], nil)
    end
    a.equal(json.decode(a.read(state_root .. "/dynamic-layout.hypr/state.json")).version, 1)
    a.equal(#json.decode(a.read(state_root .. "/dynamic-layout.hypr/state.json")).workspaces, 0)
    a.write(state_root .. "/dynamic-layout.hypr/state.json", json.encode({ version = 1, workspaces = { ["id:7"] = {
      active_layout = "tall", reflect = true, order = { "old" },
      layout_state = { tall = { ratio = 0.63 }, wide = { ratio = 0.5 }, three_col = { ratio = 1 / 3, focus_row = 1 }, fullscreen = {} }, addresses = { old = "stale" }, selected_id = "old"
    }} }))
    require("dynamic_layout").setup()
    local saved = json.decode(a.read(state_root .. "/dynamic-layout.hypr/state.json")).workspaces["id:7"]
    a.equal(saved.active_layout, "tall")
    a.equal(saved.reflect, true)
    a.near(saved.layout_state.tall.ratio, 0.63)
    a.equal(saved.selected_id, nil)
    a.equal(next(saved.addresses), nil)
    a.equal(#saved.order, 0)
  end,

}
