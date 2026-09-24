local Registry = require("dynamic_layout.framework.registry")
local Store = require("dynamic_layout.framework.store")
local Engine = require("dynamic_layout.framework.engine")

local M = {}
local sequence = 0

function M.path(name)
    sequence = sequence + 1
    return assert(os.getenv("XDG_STATE_HOME"), "run tests/test.sh to isolate state") .. "/" .. sequence .. "-" .. name
end

function M.registry()
    return Registry.new({
        (require("dynamic_layout.strategies.tall")),
        (require("dynamic_layout.strategies.wide")),
        (require("dynamic_layout.strategies.three_col")),
        (require("dynamic_layout.strategies.fullscreen"))
    })
end

function M.store()
    local store = Store.new(M.registry())
    local ws = assert(Store.workspace(store, { targets = {} }, { id = 7 }))
    ws.layout_state.tall.ratio = 0.61
    ws.layout_state.wide.ratio = 0.72
    ws.layout_state.three_col.ratio = 1 / 3
    ws.reflect = true
    ws.active_layout = store.registry.by_name.fullscreen
    ws.order = { "a", "b" }
    ws.addresses = { a = "abc", b = "def" }
    ws.selected_id = "b"
    return store, ws
end

function M.hyprland()
    local env = { registered = {}, hooks = {}, dispatched = {}, windows = {}, focused_workspace = { id = 10 } }
    ---@diagnostic disable-next-line: missing-fields
    _G.hl = {
        layout = {
            register = function (name, definition)
                env.registered[name] = definition
            end
        },
        on = function (event, callback)
            env.hooks[event] = callback
        end,
        dispatch = function (value)
            env.dispatched[#env.dispatched + 1] = value
        end,
        get_active_window = function () return env.active_window end,
        get_active_workspace = function () return env.focused_workspace end,
        get_windows = function () return env.windows end,
        dsp = {
            layout = function (message) return message end,
            focus = function (options) return options end,
            window = { cycle_next = function (options) return options end }
        }
    }
    return env
end

function M.engine(window_count)
    local env = M.hyprland()
    env.state_path, env.status_path = M.path("settings"), M.path("status")
    -- Capture the store at its construction boundary for internal state tests;
    -- production controllers do not expose mutable engine state.
    local new_store = Store.new
    ---@diagnostic disable-next-line: duplicate-set-field
    Store.new = function(registry)
        env.store = new_store(registry)
        return env.store
    end
    local ok, controller = pcall(Engine.register, {
        registry = M.registry(),
        state_path = env.state_path,
        status_path = env.status_path
    })
    Store.new = new_store
    assert(ok, controller)
    env.controller = controller
    env.empty = { targets = {}, area = { x = 0, y = 0, w = 100, h = 100 } }
    env.registered.dynamic.layout_msg(env.empty, "fullscreen")
    env.context = { area = env.empty.area, targets = {} }
    env.boxes = {}
    for i = 1, window_count or 3 do
        local window = {
            workspace = { id = 10 },
            stable_id = i,
            address = "window" .. i,
            active = i == 2,
            mapped = true,
            floating = false,
            layout = { name = "lua:dynamic" }
        }
        env.windows[i] = window
        env.context.targets[i] = {
            index = i,
            window = window,
            place = function (_, box)
                env.boxes[i] = box
            end
        }
    end
    env.registered.dynamic.recalculate(env.context)
    env.ws = env.store.workspaces["id:10"]
    return env
end

function M.focus(env, index)
    for i, window in ipairs(env.windows) do
        window.active = i == index
    end
    env.active_window = env.windows[index]
    env.hooks["window.active"](env.active_window)
end

return M
