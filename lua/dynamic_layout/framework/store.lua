local util = require("dynamic_layout.framework.util")

---@class LayoutStore
---@field registry   LayoutRegistry
---@field workspaces table<string, LayoutWorkspaceState>
local Store = {}

---@class LayoutWorkspaceState
---@field order         string[]
---@field addresses     table<string, string>
---@field reflect       boolean
---@field active_layout LayoutStrategy
---@field layout_state  table<string, table>
---@field selected_id?  string

function Store.new_workspace(registry)
    local layout_state = {}
    for _, layout in ipairs(registry.layouts) do
        layout_state[layout.name] = layout.new_state()
    end

    return {
        order = {},
        addresses = {},
        reflect = false,
        active_layout = registry.default_layout,
        layout_state = layout_state
    }
end

function Store.workspace_key(workspace)
    if workspace == nil then
        return nil
    end

    if type(workspace) ~= "table" and type(workspace) ~= "userdata" then
        return tostring(workspace)
    end

    local id = util.field(workspace, "id")
    if id ~= nil then
        return "id:" .. tostring(id)
    end

    local name = util.field(workspace, "name")
    if name ~= nil then
        return "name:" .. tostring(name)
    end

    return tostring(workspace)
end

function Store.window_workspace_key(window)
    return Store.workspace_key(util.field(window, "workspace"))
end

function Store.target_id(target)
    local window = target.window
    local stable_id = window and util.field(window, "stable_id")
    return stable_id ~= nil and tostring(stable_id) or tostring(target.index)
end

local function target_address(target)
    local window = util.field(target, "window")
    local address = util.field(window, "address")
    return address and tostring(address)
end

function Store.context_key(ctx, fallback_workspace)
    local key
    for _, target in ipairs(ctx.targets or {}) do
        key = Store.window_workspace_key(util.field(target, "window"))
        if key then
            return key
        end
    end

    return Store.workspace_key(fallback_workspace)
end

function Store.workspace(store, ctx, fallback_workspace)
    local key = Store.context_key(ctx, fallback_workspace)
    if not key then return nil end
    local ws = store.workspaces[key]
    if not ws then
        ws = Store.new_workspace(store.registry)
        store.workspaces[key] = ws
    end

    return ws
end

function Store.layout_label(ws)
    local layout = ws.active_layout
    local label = layout.label(ws.layout_state[layout.name])
    return ws.reflect and (label .. ":R") or label
end

function Store.active_id(ctx, ws)
    for _, target in ipairs(ctx.targets) do
        local window = target.window
        if window and window.active then
            ws.selected_id = Store.target_id(target)
            return ws.selected_id
        end
    end

    if not util.index_of(ws.order, ws.selected_id) then ws.selected_id = ws.order[1] end
    return ws.selected_id
end

function Store.sync_order(ctx, ws)
    local present = {}
    local targets = {}
    local addresses = {}

    for _, target in ipairs(ctx.targets) do
        local id = Store.target_id(target)
        present[id] = true
        targets[id] = target
        addresses[id] = target_address(target)
    end

    local old_order = ws.order
    local selected_index = util.index_of(old_order, ws.selected_id) or 1
    ws.order = {}
    ws.addresses = {}

    for _, id in ipairs(old_order) do
        if present[id] then
            table.insert(ws.order, id)
            ws.addresses[id] = addresses[id]
        end
    end

    for _, target in ipairs(ctx.targets) do
        local id = Store.target_id(target)
        if not util.index_of(ws.order, id) then
            table.insert(ws.order, id)
            ws.addresses[id] = addresses[id]
        end
    end

    if not present[ws.selected_id] then
        ws.selected_id = ws.order[math.min(selected_index, #ws.order)]
    end
    return targets
end

function Store.promote_active(ctx, ws)
    local id = Store.active_id(ctx, ws)
    local i = id and util.index_of(ws.order, id)
    if not i then
        return
    end

    table.remove(ws.order, i)
    table.insert(ws.order, 1, id)
end

function Store.swap_active(ctx, ws, next)
    local id = Store.active_id(ctx, ws)
    local i = id and util.index_of(ws.order, id)
    if not i or #ws.order < 2 then
        return
    end

    local target = next and (i + 1) or (i - 1)
    if target > #ws.order then
        target = 1
    elseif target < 1 then
        target = #ws.order
    end

    ws.order[i], ws.order[target] = ws.order[target], ws.order[i]
end

function Store.demote_active(ctx, ws)
    local id = Store.active_id(ctx, ws)
    local i = id and util.index_of(ws.order, id)
    if not i or i ~= 1 or #ws.order < 2 then
        return
    end

    table.remove(ws.order, i)
    table.insert(ws.order, id)
end

function Store.swap_active_with(ctx, ws, target_id_value)
    local active = Store.active_id(ctx, ws)
    local active_index = active and util.index_of(ws.order, active)
    local target_index = target_id_value and util.index_of(ws.order, target_id_value)
    if not active_index or not target_index then
        return
    end

    ws.order[active_index], ws.order[target_index] = ws.order[target_index], ws.order[active_index]
end

-- Remove a closed/moved window without needing a non-empty layout context.
function Store.remove_window(store, id, destination_key)
    if not id then return end
    for key, ws in pairs(store.workspaces) do
        if key ~= destination_key then
            local index = util.index_of(ws.order, id)
            if index then
                table.remove(ws.order, index)
                ws.addresses[id] = nil
                if ws.selected_id == id then
                    ws.selected_id = ws.order[math.min(index, #ws.order)]
                end
            end
        end
    end
end

function Store.clear_workspace(store, workspace)
    local ws = store.workspaces[Store.workspace_key(workspace)]
    if ws then
        ws.order, ws.addresses, ws.selected_id = {}, {}, nil
    end
end

-- Empty layout contexts have no workspace identity. Reconcile known entries
-- against the compositor instead of guessing from the focused workspace.
function Store.prune(store, windows)
    local live = {}
    for _, window in ipairs(windows) do
        if window.mapped and not window.floating then
            live[tostring(window.stable_id)] = Store.window_workspace_key(window)
        end
    end
    for key, ws in pairs(store.workspaces) do
        for i = #ws.order, 1, -1 do
            local id = ws.order[i]
            if live[id] ~= key then
                table.remove(ws.order, i)
                ws.addresses[id] = nil
                if ws.selected_id == id then ws.selected_id = ws.order[math.min(i, #ws.order)] end
            end
        end
    end
end

function Store.workspace_for_window(store, window)
    return store.workspaces[Store.window_workspace_key(window)]
end

---@param registry LayoutRegistry
---@return LayoutStore
function Store.new(registry)
    return { registry = registry, workspaces = {} }
end

return Store
