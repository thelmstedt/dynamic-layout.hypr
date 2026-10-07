---@class LayoutRegistryModule
local Registry = {}

---@class LayoutStrategy<S>
--- State is fresh per workspace/reset and persists as JSON. Context/order are read-only.
--- geometry returns an id -> box map in canonical (unreflected) orientation; the
--- framework mirrors it when reflect_axis is set and the workspace is reflected,
--- places the result, and derives directional navigation from it.
--- Define neighbor only to override that default, e.g. to track focus history
--- (purpose distinguishes focus from swapping) or navigate a persisted structure.
--- on_focused_changed tracks navigation history; needs_focus_recalculate enables focus-dependent placement.
---@field name                     string
---@field reflect_axis?            "x"|"y" Mirror axis for reflection; omit to ignore the workspace reflect toggle.
---@field single_window?           boolean Whether only one window is visible at a time; defaults to false.
---@field needs_focus_recalculate? boolean
---@field new_state                fun(): S
---@field geometry                 fun(state: S, context: HL.LayoutContext, workspace: WorkspaceContext): table<string, HL.Box>
---@field neighbor?                fun(state: S, direction: LayoutDirection, workspace: WorkspaceContext, purpose?: "focus"|"swap"): string?
---@field on_focused_changed?      fun(state: S, ids: string[], active_id: string?)

---@param strategy LayoutStrategy
---@param index integer
local function validate(strategy, index)
    local name = "strategies[" .. tostring(index) .. "]"
    assert(type(strategy) == "table", name .. " must be a table")
    for _, method in ipairs({ "new_state", "geometry" }) do
        assert(type(strategy[method]) == "function", name .. "." .. method .. " must be a function")
    end
    for _, method in ipairs({ "neighbor", "on_focused_changed" }) do
        assert(strategy[method] == nil or type(strategy[method]) == "function", name .. "." .. method .. " must be a function")
    end
    assert(
        strategy.single_window == nil or type(strategy.single_window) == "boolean",
        name .. ".single_window must be a boolean"
    )
    assert(
        strategy.reflect_axis == nil or strategy.reflect_axis == "x" or strategy.reflect_axis == "y",
        name .. '.reflect_axis must be "x" or "y"'
    )
end

---@param strategies LayoutStrategy[]
---@return LayoutRegistry
function Registry.new(strategies)
    assert(type(strategies) == "table" and #strategies > 0, "at least one layout strategy is required")

    ---@type LayoutRegistry
    local instance = { layouts = strategies, by_name = {}, names = {} }

    for index, strategy in ipairs(strategies) do
        validate(strategy, index)
        assert(type(strategy.name) == "string" and strategy.name ~= "", "strategy name is required")
        assert(strategy.name ~= "_refresh", "strategy name is reserved: _refresh")
        assert(not instance.by_name[strategy.name], "duplicate strategy name: " .. strategy.name)
        instance.by_name[strategy.name] = strategy

        table.insert(instance.names, strategy.name)
    end

    return instance
end

---@class LayoutRegistry
---@field by_name       table<string, LayoutStrategy>
---@field layouts       LayoutStrategy[]
---@field names         string[]

return Registry
