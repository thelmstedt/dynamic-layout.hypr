local Store = require("dynamic_layout.framework.store")
local Persistence = require("dynamic_layout.framework.persistence")
local util = require("dynamic_layout.framework.util")

local Engine = {}

local engine_messages = {
    "swapwithmaster", "promote", "demote", "swapnext", "swapprev", "swapdirection <l|r|u|d>", "nextlayout", "prevlayout",
    "reflect", "reset"
}

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
    local expected_messages = { table.unpack(engine_messages) }
    for _, message in ipairs(registry.messages) do
        table.insert(expected_messages, message)
    end

    local function is_managed_layout(window)
        if not window or window.floating then return false end
        local layout_name = util.field(window and window.layout, "name")
        return layout_name == name or layout_name == "lua:" .. name
    end

    local function reset(ws)
        ws.reflect = false
        for _, layout in ipairs(layouts) do
            ws.layout_state[layout.name] = layout.new_state()
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

    local definition = {
        recalculate = function (ctx)
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
        end,

        layout_msg = function (ctx, msg)
            -- Messages target the focused workspace, including when it has no tiles.
            -- Recalculation must not use this fallback: it can run for other workspaces.
            local ws = Store.workspace(store, ctx, hl.get_active_workspace())
            if not ws then return name .. ": no workspace for layout message" end
            Store.sync_order(ctx, ws)
            local command, arg = msg:match("^(%S+)%s*(.*)$")
            local context = { active_id = Store.active_id(ctx, ws), order = ws.order, reflect = ws.reflect }
            local selected_layout = registry.commands[command]

            if selected_layout then
                ws.active_layout = selected_layout
            elseif ws.active_layout.handle(ws.layout_state[ws.active_layout.name], command, arg, ctx, context) then
                -- Strategy-specific command.
            elseif command == "swapwithmaster" then
                Store.swap_active_with(ctx, ws, ws.order[1])
            elseif command == "promote" then
                Store.promote_active(ctx, ws)
            elseif command == "demote" then
                Store.demote_active(ctx, ws)
            elseif command == "swapnext" or command == "swapprev" then
                Store.swap_active(ctx, ws, command == "swapnext")
            elseif command == "swapdirection" and arg:match("^[lrud]$") then
                local neighbor = ws.active_layout.neighbor(ws.order, context.active_id, arg, context)
                Store.swap_active_with(ctx, ws, neighbor)
            elseif command == "nextlayout" or command == "prevlayout" then
                cycle_layout(ws, command == "nextlayout")
            elseif command == "reflect" then
                ws.reflect = not ws.reflect
            elseif command == "reset" then
                reset(ws)
            else
                return "dynamic-layout.hypr\nreceived command " .. tostring(command)
                    .. "\nexpected " .. table.concat(expected_messages, ", ")
            end

            publish()
            return true
        end
    }

    hl.layout.register(name, definition)
    hl.on("window.close", function (window)
        local id = util.field(window, "stable_id")
        Store.remove_window(store, id and tostring(id))
        publish()
    end)
    hl.on("window.move_to_workspace", function (window, destination)
        local id = util.field(window, "stable_id")
        Store.remove_window(store, id and tostring(id), Store.workspace_key(destination))
        publish()
    end)
    hl.on("workspace.removed", function (workspace)
        Store.clear_workspace(store, workspace)
        publish()
    end)
    hl.on("window.active", function (window)
        local ws = Store.workspace_for_window(store, window)
        local id = util.field(window, "stable_id")
        id = id and tostring(id)
        if ws and util.index_of(ws.order, id) and is_managed_layout(window) then
            ws.active_layout.focus_changed(ws.layout_state[ws.active_layout.name], id, ws.order)
            ws.selected_id = id
            if ws.active_layout.needs_focus_recalculate then
                hl.dispatch(hl.dsp.layout("focusactive"))
            end
        end
    end)

    local controller = { name = name, store = store, definition = definition, publish = publish }
    publish()

    -- Dispatch through Hyprland so actions use its current layout context and
    -- trigger recalculation. These closures can be passed directly to hl.bind.
    local function action(message)
        return function ()
            hl.dispatch(hl.dsp.layout(message))
        end
    end

    controller.reset = action("reset")
    controller.reflect = action("reflect")
    controller.grow = action("grow")
    controller.shrink = action("shrink")
    controller.promote = action("promote")
    controller.demote = action("demote")
    controller.swap_with_master = action("swapwithmaster")
    controller.next_layout = action("nextlayout")
    controller.prev_layout = action("prevlayout")
    controller.focus_next = function ()
        controller.cycle_focus(true)
    end
    controller.focus_prev = function ()
        controller.cycle_focus(false)
    end
    controller.swap_next = function ()
        controller.swap_active(true)
    end
    controller.swap_prev = function ()
        controller.swap_active(false)
    end

    function controller.set_ratio(ratio)
        assert(type(ratio) == "number" and ratio >= 0.1 and ratio <= 0.9, "ratio must be a number between 0.1 and 0.9")
        hl.dispatch(hl.dsp.layout("ratio " .. tostring(ratio)))
    end

    function controller.cycle_focus(next)
        local window = hl.get_active_window()
        local ws = Store.workspace_for_window(store, window)
        if not ws or not is_managed_layout(window) then
            hl.dispatch(hl.dsp.window.cycle_next({ next = next }))
            return
        end

        local order = ws.order
        local id = util.field(window, "stable_id")
        local current = id and util.index_of(order, tostring(id))
        if not current or #order == 0 then return end

        local target = next and current + 1 or current - 1
        if target > #order then
            target = 1
        elseif target < 1 then
            target = #order
        end
        local address = ws.addresses[order[target]]
        if address then hl.dispatch(hl.dsp.focus({ window = "address:" .. address })) end
    end

    function controller.swap_active(next)
        local window = hl.get_active_window()
        if Store.workspace_for_window(store, window) and is_managed_layout(window) then
            hl.dispatch(hl.dsp.layout(next and "swapnext" or "swapprev"))
        end
    end

    --- Move focus using the same neighbors as directional swapping.
    ---@param direction "l" | "r" | "u" | "d"
    function controller.move_direction(direction)
        local window = hl.get_active_window()
        local ws = Store.workspace_for_window(store, window)
        if not ws or not is_managed_layout(window) then
            hl.dispatch(hl.dsp.focus({ direction = direction }))
            return
        end

        local id = util.field(window, "stable_id")
        local context = { active_id = id and tostring(id), order = ws.order, reflect = ws.reflect }
        local strategy = ws.active_layout
        local neighbor = strategy.focus_neighbor(
            ws.layout_state[strategy.name], ws.order, context.active_id, direction, context
        )
        local address = neighbor and ws.addresses[neighbor]
        if address then hl.dispatch(hl.dsp.focus({ window = "address:" .. address })) end
    end

    ---@param direction "l" | "r" | "u" | "d"
    function controller.swap_direction(direction)
        hl.dispatch(hl.dsp.layout("swapdirection " .. direction))
    end

    return controller
end

---@class LayoutController
---@field name             string
---@field store            LayoutStore
---@field definition       HL.LayoutProvider
---@field publish          fun()
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
