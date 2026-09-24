local a = require("tests.support.assertions")
local fixture = require("tests.support.fixtures")

return {
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
    a.equal(a.read(state_root .. "/dynamic-layout.hypr/settings"):sub(1, 1), "#")
    a.equal(a.read(state_root .. "/dynamic-layout.hypr/status"), "")
    a.write(state_root .. "/dynamic-layout.hypr/status", "stale addresses")
    require("dynamic_layout").setup()
    a.equal(a.read(state_root .. "/dynamic-layout.hypr/status"), "")
  end,

}
