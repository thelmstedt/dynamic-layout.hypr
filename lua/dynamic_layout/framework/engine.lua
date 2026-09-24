local Store = require("dynamic_layout.framework.store")
local Persistence = require("dynamic_layout.framework.persistence")
local util = require("dynamic_layout.framework.util")

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
    local function report(message)
        print("dynamic_layout: " .. message)
    end
    Persistence.load(store, options.state_path, report)
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

    local function is_managed_layout(window)
        if not window or window.floating then return false end
        local layout_name = util.field(window.layout, "name")
        return layout_name == name or layout_name == "lua:" .. name
    end

    local function window_id(window)
        local id = util.field(window, "stable_id")
        return id and tostring(id)
    end

    local function focus_window(ws, id)
        local address = id and ws.addresses[id]
        if address then hl.dispatch(hl.dsp.focus({ window = "address:" .. address })) end
    end

    local function recalculate(ctx)
        if not ctx.targets or #ctx.targets == 0 then
            Store.prune(store, hl.get_windows())
            publish()
            return
        end

        local ws = Store.workspace(store, ctx)
        if not ws then return end
        local targets = Store.sync_order(ctx, ws)
        if #ws.order == 0 then return end

        ws.active_layout.place(ctx, targets, ws.order, ws.layout_state[ws.active_layout.name], {
            active_id = Store.active_id(ctx, ws),
            order = ws.order,
            reflect = ws.reflect
        })
        publish()
    end

    local function layout_msg(ctx, msg)
        if msg == "_refresh" then return true end
        local selected_layout = registry.commands[msg]
        if not selected_layout then
            return "dynamic-layout.hypr: expected " .. table.concat(registry.commands_list, ", ")
        end
        local ws = Store.workspace(store, ctx, hl.get_active_workspace())
        if not ws then return name .. ": no workspace for layout message" end
        ws.active_layout = selected_layout

        publish()
        return true
    end

    local function window_closed(window)
        Store.remove_window(store, window_id(window))
        publish()
    end

    local function window_moved(window, destination)
        Store.remove_window(store, window_id(window), Store.workspace_key(destination))
        publish()
    end

    local function workspace_removed(workspace)
        Store.clear_workspace(store, workspace)
        publish()
    end

    local function window_activated(window)
        local ws = Store.workspace_for_window(store, window)
        local id = window_id(window)
        if ws and util.index_of(ws.order, id) and is_managed_layout(window) then
            ws.active_layout.focus_changed(ws.layout_state[ws.active_layout.name], id, ws.order)
            ws.selected_id = id
            if ws.active_layout.needs_focus_recalculate then
                refresh()
            end
        end
    end

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

    local function context(ws)
        return { active_id = ws.selected_id, order = ws.order, reflect = ws.reflect }
    end

    local function resize(ws, delta)
        ws.active_layout.resize(ws.layout_state[ws.active_layout.name], delta, context(ws))
    end

    local function reset(ws)
        ws.reflect = false
        for _, layout in ipairs(layouts) do
            ws.layout_state[layout.name] = layout.new_state()
        end
    end

    local function reflect(ws)
        ws.reflect = not ws.reflect
    end

    local function promote(ws)
        Store.promote_active(ws, ws.selected_id)
    end

    local function demote(ws)
        Store.demote_active(ws, ws.selected_id)
    end

    local function swap_with_master(ws)
        Store.swap_active_with(ws, ws.selected_id, ws.order[1])
    end

    local function set_ratio(ws, ratio)
        assert(type(ratio) == "number" and ratio >= 0.1 and ratio <= 0.9, "ratio must be a number between 0.1 and 0.9")
        ws.active_layout.set_ratio(ws.layout_state[ws.active_layout.name], ratio)
    end

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

    local function swap_active(ws, next)
        local window = hl.get_active_window()
        if Store.workspace_for_window(store, window) ~= ws or not is_managed_layout(window) then return false end
        Store.swap_active(ws, ws.selected_id, next)
    end

    --- Move focus using the same neighbors as directional swapping.
    ---@param direction "l" | "r" | "u" | "d"
    local function move_direction(direction)
        local window = hl.get_active_window()
        local ws = Store.workspace_for_window(store, window)
        if not ws or not is_managed_layout(window) then
            hl.dispatch(hl.dsp.focus({ direction = direction }))
            return
        end

        local context = { active_id = window_id(window), order = ws.order, reflect = ws.reflect }
        local strategy = ws.active_layout
        local neighbor = strategy.focus_neighbor(
            ws.layout_state[strategy.name], ws.order, context.active_id, direction, context
        )
        focus_window(ws, neighbor)
    end

    ---@param direction "l" | "r" | "u" | "d"
    local function swap_direction(ws, direction)
        local neighbor = ws.active_layout.neighbor(ws.order, ws.selected_id, direction, context(ws))
        Store.swap_active_with(ws, ws.selected_id, neighbor)
    end

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

    return {
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
---@field move_direction   fun(direction: "l" | "r" | "u" | "d")
---@field swap_direction   fun(direction: "l" | "r" | "u" | "d")

return Engine
