local util = require("dynamic_layout.framework.util")

---@class LayoutStore
---@field registry   LayoutRegistry
---@field workspaces table<string, LayoutWorkspaceState>

---@class LayoutWorkspaceState
---@field order         string[]
---@field addresses     table<string, string>
---@field reflect       boolean
---@field active_layout LayoutStrategy
---@field layout_state  table<string, LayoutStrategyState>
---@field selected_id?  string

-- Strategy-specific fields stay typed in LayoutStrategy<S>. The store's
-- name-indexed map exposes only the state shared with the framework.
---@class LayoutStrategyState
---@field ratio? number

-- Store operations only need the target list, not Hyprland's geometry helpers.
---@alias StoreContext { targets: HL.LayoutTarget[] }
---@alias WorkspaceReference HL.Workspace|{ id?: integer, name?: string }|string|number

---@class LayoutStoreModule
local Store = {}

---@param registry LayoutRegistry
---@return LayoutWorkspaceState
function Store.new_workspace(registry)
    ---@type table<string, LayoutStrategyState>
    local layout_state = {}
    for _, layout in ipairs(registry.layouts) do
        layout_state[layout.name] = layout.new_state()
    end

    return {
        order = {},
        addresses = {},
        reflect = false,
        active_layout = registry.layouts[1],
        layout_state = layout_state
    }
end

---@param workspace WorkspaceReference?
---@return string?
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

---@param window HL.Window?
---@return string?
function Store.window_workspace_key(window)
    return Store.workspace_key(util.field(window, "workspace"))
end

---@param target HL.LayoutTarget
---@return string
function Store.target_id(target)
    local window = target.window
    local stable_id = window and util.field(window, "stable_id")
    return stable_id ~= nil and tostring(stable_id) or tostring(target.index)
end

---@param target HL.LayoutTarget
---@return string?
local function target_address(target)
    local window = util.field(target, "window")
    local address = util.field(window, "address")
    return address and tostring(address)
end

---@param layout_context StoreContext
---@param fallback_workspace WorkspaceReference?
---@return string?
function Store.context_key(layout_context, fallback_workspace)
    local key
    for _, target in ipairs(layout_context.targets or {}) do
        key = Store.window_workspace_key(util.field(target, "window"))
        if key then
            return key
        end
    end

    return Store.workspace_key(fallback_workspace)
end

---@param store LayoutStore
---@param workspace WorkspaceReference?
---@return LayoutWorkspaceState?
function Store.for_workspace(store, workspace)
    local key = Store.workspace_key(workspace)
    if not key then return nil end
    local ws = store.workspaces[key]
    if not ws then
        ws = Store.new_workspace(store.registry)
        store.workspaces[key] = ws
    end

    return ws
end

---@param store LayoutStore
---@param layout_context StoreContext
---@param fallback_workspace WorkspaceReference?
---@return LayoutWorkspaceState?
function Store.workspace(store, layout_context, fallback_workspace)
    return Store.for_workspace(store, Store.context_key(layout_context, fallback_workspace))
end

---@param ws LayoutWorkspaceState
---@return string
function Store.layout_label(ws)
    local layout = ws.active_layout
    local label = util.ratio_label(layout.name:upper(), ws.layout_state[layout.name].ratio)
    return ws.reflect and (label .. ":R") or label
end

---@param ws LayoutWorkspaceState
---@param layout_context StoreContext
---@return string?
function Store.active_id(ws, layout_context)
    for _, target in ipairs(layout_context.targets) do
        local window = target.window
        if window and window.active then
            ws.selected_id = Store.target_id(target)
            return ws.selected_id
        end
    end

    if not util.index_of(ws.order, ws.selected_id) then ws.selected_id = ws.order[1] end
    return ws.selected_id
end

-- Prune against live windows before syncing. A recalculation may contain only
-- part of a workspace while Hyprland rebuilds its layout during reload.
---@param ws LayoutWorkspaceState
---@param layout_context StoreContext
---@return table<string, HL.LayoutTarget> targets
---@return string[] order Window IDs available for this placement pass.
function Store.sync_order(ws, layout_context)
    ---@type table<string, HL.LayoutTarget>
    local targets = {}
    ws.addresses = {}

    for _, target in ipairs(layout_context.targets) do
        local id = Store.target_id(target)
        targets[id] = target
        ws.addresses[id] = target_address(target)
        if not util.index_of(ws.order, id) then
            table.insert(ws.order, id)
        end
    end

    ---@type string[]
    local order = {}
    for _, id in ipairs(ws.order) do
        if targets[id] then order[#order + 1] = id end
    end
    return targets, order
end

---@param ws LayoutWorkspaceState
---@param id string?
function Store.promote_active(ws, id)
    local i = id and util.index_of(ws.order, id)
    if not i then
        return
    end

    table.remove(ws.order, i)
    table.insert(ws.order, 1, id)
end

---@param ws LayoutWorkspaceState
---@param id string?
---@param next boolean
function Store.swap_active(ws, id, next)
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

---@param ws LayoutWorkspaceState
---@param id string?
function Store.demote_active(ws, id)
    local i = id and util.index_of(ws.order, id)
    if not i or i ~= 1 or #ws.order < 2 then
        return
    end

    table.remove(ws.order, i)
    table.insert(ws.order, id)
end

---@param ws LayoutWorkspaceState
---@param active_id string?
---@param target_id string?
function Store.swap_active_with(ws, active_id, target_id)
    local active_index = active_id and util.index_of(ws.order, active_id)
    local target_index = target_id and util.index_of(ws.order, target_id)
    if not active_index or not target_index then
        return
    end

    ws.order[active_index], ws.order[target_index] = ws.order[target_index], ws.order[active_index]
end

-- Remove a closed/moved window without needing a non-empty layout context.
---@param store LayoutStore
---@param id string?
---@param destination_key string?
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

---@param store LayoutStore
---@param workspace WorkspaceReference?
function Store.clear_workspace(store, workspace)
    local ws = store.workspaces[Store.workspace_key(workspace)]
    if ws then
        ws.order, ws.addresses, ws.selected_id = {}, {}, nil
    end
end

-- Reconcile against live compositor windows: a partial layout target list
-- does not mean that the missing windows have closed or left the workspace.
---@param store LayoutStore
---@param windows HL.Window[]
function Store.prune(store, windows)
    ---@type table<string, string>
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

---@param store LayoutStore
---@param window HL.Window?
---@return LayoutWorkspaceState?
function Store.workspace_for_window(store, window)
    return store.workspaces[Store.window_workspace_key(window)]
end

---@param registry LayoutRegistry
---@return LayoutStore
function Store.new(registry)
    return { registry = registry, workspaces = {} }
end

return Store
