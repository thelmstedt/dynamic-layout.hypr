local Store = require("dynamic_layout.framework.store")
local Persistence = require("dynamic_layout.framework.persistence")
local util = require("dynamic_layout.framework.util")

---@class LayoutEngineModule
local Engine = {}

---@class LayoutEngineOptions
---@field registry    LayoutRegistry
---@field state_path  string
---@field status_path string

---@param options LayoutEngineOptions
---@return LayoutController
function Engine.register(options)
    assert(options.registry, "layout registry is required")
    assert(type(options.state_path) == "string" and options.state_path ~= "", "layout state path is required")
    assert(type(options.status_path) == "string" and options.status_path ~= "", "layout status path is required")
    assert(options.state_path ~= options.status_path, "state and status paths must differ")

    local name = "dynamic"
    local registry = options.registry
    local layouts = registry.layouts
    local store = Store.new(registry)
    ---@param message string
    local function report(message)
        print("dynamic_layout: " .. message)
    end
    Persistence.load(store, options.state_path, report)
    Store.prune(store, hl.get_windows())
    local settings_writer = Persistence.writer(options.state_path, report)
    local status_writer = Persistence.writer(options.status_path, report)
    local function publish()
        Persistence.write(settings_writer, Persistence.settings(store))
        Persistence.write(status_writer, Persistence.status(store))
    end
    -- Hyprland has no separate Lua recalculation request. This message carries
    -- no operation: controller methods have already changed workspace state.
    local function refresh()
        hl.dispatch(hl.dsp.layout("_refresh"))
    end

    ---@param window HL.Window?
    ---@return boolean
    local function is_managed_layout(window)
        if not window or window.floating then return false end
        local layout_name = util.field(window.layout, "name")
        return layout_name == name or layout_name == "lua:" .. name
    end

    ---@param window HL.Window?
    ---@return string?
    local function window_id(window)
        local id = util.field(window, "stable_id")
        return id and tostring(id)
    end

    ---@param ws LayoutWorkspaceState
    ---@param id string?
    local function focus_window(ws, id)
        local address = id and ws.addresses[id]
        if address then hl.dispatch(hl.dsp.focus({ window = "address:" .. address })) end
    end

    ---@param layout_context HL.LayoutContext
    local function recalculate(layout_context)
        Store.prune(store, hl.get_windows())
        if not layout_context.targets or #layout_context.targets == 0 then
            publish()
            return
        end

        local ws = Store.workspace(store, layout_context)
        if not ws then return end
        local targets, order = Store.sync_order(ws, layout_context)
        if #order == 0 then return end

        ws.active_layout.place(ws.layout_state[ws.active_layout.name], layout_context, targets, {
            active_id = Store.active_id(ws, layout_context),
            order = order,
            reflect = ws.reflect
        })
        publish()
    end

    ---@param layout_context HL.LayoutContext
    ---@param msg string
    ---@return boolean|string
    local function layout_msg(layout_context, msg)
        if msg == "_refresh" then return true end
        local selected_layout = registry.by_name[msg]
        if not selected_layout then
            return "dynamic-layout.hypr: expected " .. table.concat(registry.names, ", ")
        end
        local ws = Store.workspace(store, layout_context, hl.get_active_workspace())
        if not ws then return name .. ": no workspace for layout message" end
        ws.active_layout = selected_layout

        publish()
        return true
    end

    ---@param window HL.Window
    local function window_closed(window)
        Store.remove_window(store, window_id(window))
        publish()
    end

    ---@param window HL.Window
    ---@param destination HL.Workspace
    local function window_moved(window, destination)
        Store.remove_window(store, window_id(window), Store.workspace_key(destination))
        publish()
    end

    ---@param workspace HL.Workspace
    local function workspace_removed(workspace)
        Store.clear_workspace(store, workspace)
        publish()
    end

    ---@param window HL.Window?
    local function window_activated(window)
        local ws = Store.workspace_for_window(store, window)
        local id = window_id(window)
        if ws and util.index_of(ws.order, id) and is_managed_layout(window) then
            local strategy = ws.active_layout
            if strategy.on_focused_changed then
                strategy.on_focused_changed(ws.layout_state[strategy.name], ws.order, id)
            end
            ws.selected_id = id
            if ws.active_layout.needs_focus_recalculate then
                refresh()
            end
        end
    end

    ---@param ws LayoutWorkspaceState
    ---@param next boolean
    local function cycle_layout(ws, next)
        local current = util.index_of(layouts, ws.active_layout) or 1
        local target = next and current + 1 or current - 1
        if target > #layouts then
            target = 1
        elseif target < 1 then
            target = #layouts
        end
        ws.active_layout = layouts[target]
    end

    ---@param ws LayoutWorkspaceState
    ---@return WorkspaceContext
    local function workspace_context(ws)
        return { active_id = ws.selected_id, order = ws.order, reflect = ws.reflect }
    end

    ---@param ws LayoutWorkspaceState
    ---@param delta number
    ---@return false|nil
    local function resize(ws, delta)
        local state = ws.layout_state[ws.active_layout.name]
        if state.ratio == nil then return false end
        util.resize_ratio(state, delta, workspace_context(ws))
    end

    ---@param ws LayoutWorkspaceState
    local function reset(ws)
        ws.reflect = false
        for _, layout in ipairs(layouts) do
            ws.layout_state[layout.name] = layout.new_state()
        end
    end

    ---@param ws LayoutWorkspaceState
    local function reflect(ws)
        ws.reflect = not ws.reflect
    end

    ---@param ws LayoutWorkspaceState
    local function promote(ws)
        Store.promote_active(ws, ws.selected_id)
    end

    ---@param ws LayoutWorkspaceState
    local function demote(ws)
        Store.demote_active(ws, ws.selected_id)
    end

    ---@param ws LayoutWorkspaceState
    local function swap_with_master(ws)
        Store.swap_active_with(ws, ws.selected_id, ws.order[1])
    end

    ---@param ws LayoutWorkspaceState
    ---@param ratio number
    ---@return false|nil
    local function set_ratio(ws, ratio)
        assert(type(ratio) == "number" and ratio >= 0.1 and ratio <= 0.9, "ratio must be a number between 0.1 and 0.9")
        local state = ws.layout_state[ws.active_layout.name]
        if state.ratio == nil then return false end
        util.set_ratio(state, ratio)
    end

    ---@param next boolean
    local function cycle_focus(next)
        local window = hl.get_active_window()
        local ws = Store.workspace_for_window(store, window)
        if not ws or not is_managed_layout(window) then
            hl.dispatch(hl.dsp.window.cycle_next({ next = next }))
            return
        end

        local order = ws.order
        local current = util.index_of(order, window_id(window))
        if not current or #order == 0 then return end

        local target = next and current + 1 or current - 1
        if target > #order then
            target = 1
        elseif target < 1 then
            target = #order
        end
        focus_window(ws, order[target])
    end

    ---@param ws LayoutWorkspaceState
    ---@param next boolean
    ---@return false|nil
    local function swap_active(ws, next)
        local window = hl.get_active_window()
        if Store.workspace_for_window(store, window) ~= ws or not is_managed_layout(window) then return false end
        Store.swap_active(ws, ws.selected_id, next)
    end

    --- Resolve the focus neighbor, including strategy-specific navigation history.
    ---@param direction LayoutDirection
    local function move_direction(direction)
        local window = hl.get_active_window()
        local ws = Store.workspace_for_window(store, window)
        if not ws or not is_managed_layout(window) then
            hl.dispatch(hl.dsp.focus({ direction = direction }))
            return
        end

        ---@type WorkspaceContext
        local workspace = { active_id = window_id(window), order = ws.order, reflect = ws.reflect }
        local strategy = ws.active_layout
        local neighbor = strategy.neighbor(
            ws.layout_state[strategy.name], ws.order, workspace.active_id, direction, workspace, true
        )
        focus_window(ws, neighbor)
    end

    ---@param ws LayoutWorkspaceState
    ---@param direction LayoutDirection
    local function swap_direction(ws, direction)
        local strategy = ws.active_layout
        local neighbor = strategy.neighbor(
            ws.layout_state[strategy.name], ws.order, ws.selected_id, direction, workspace_context(ws), false
        )
        Store.swap_active_with(ws, ws.selected_id, neighbor)
    end

    ---@return LayoutWorkspaceState?
    local function current_workspace()
        local ws = Store.for_workspace(store, hl.get_active_workspace())
        if not ws then return nil end
        local window = hl.get_active_window()
        if Store.workspace_for_window(store, window) == ws and is_managed_layout(window) then
            local id = window_id(window)
            if id and util.index_of(ws.order, id) then ws.selected_id = id end
        end
        return ws
    end
    -- Wrap mutations only when exposing them as controller callbacks.
    -- Returning false skips publishing and refresh for an inapplicable action.
    ---@generic A
    ---@overload fun(operation: fun(ws: LayoutWorkspaceState): false|nil): fun()
    ---@param operation fun(ws: LayoutWorkspaceState, arg: A): false|nil
    ---@return fun(arg: A)
    local function action(operation)
        return function (...)
            local ws = current_workspace()
            if not ws then return end
            if operation(ws, ...) == false then return end
            publish()
            refresh()
        end
    end

    hl.layout.register(name, { recalculate = recalculate, layout_msg = layout_msg })
    hl.on("window.close", window_closed)
    hl.on("window.move_to_workspace", window_moved)
    hl.on("workspace.removed", workspace_removed)
    hl.on("window.active", window_activated)
    publish()

    ---@type LayoutController
    local controller = {
        name = name,
        reset = action(reset),
        reflect = action(reflect),
        grow = action(function (ws) return resize(ws, 0.03) end),
        shrink = action(function (ws) return resize(ws, -0.03) end),
        promote = action(promote),
        demote = action(demote),
        swap_with_master = action(swap_with_master),
        next_layout = action(function (ws) return cycle_layout(ws, true) end),
        prev_layout = action(function (ws) return cycle_layout(ws, false) end),
        focus_next = function () return cycle_focus(true) end,
        focus_prev = function () return cycle_focus(false) end,
        swap_next = action(function (ws) return swap_active(ws, true) end),
        swap_prev = action(function (ws) return swap_active(ws, false) end),
        set_ratio = action(set_ratio),
        cycle_focus = cycle_focus,
        swap_active = action(swap_active),
        move_direction = move_direction,
        swap_direction = action(swap_direction)
    }
    return controller
end

---@class LayoutController
---@field name             string
---@field reset            fun()
---@field reflect          fun()
---@field grow             fun()
---@field shrink           fun()
---@field promote          fun()
---@field demote           fun()
---@field swap_with_master fun()
---@field next_layout      fun()
---@field prev_layout      fun()
---@field focus_next       fun()
---@field focus_prev       fun()
---@field swap_next        fun()
---@field swap_prev        fun()
---@field set_ratio        fun(ratio: number)
---@field cycle_focus      fun(next: boolean)
---@field swap_active      fun(next: boolean)
---@field move_direction   fun(direction: LayoutDirection)
---@field swap_direction   fun(direction: LayoutDirection)

return Engine
