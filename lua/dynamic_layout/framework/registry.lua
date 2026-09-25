---@class LayoutRegistryModule
local Registry = {}

---@class LayoutStrategy<S>
---@field name                     string
---@field needs_focus_recalculate? boolean
---@field new_state                fun(): S
---@field neighbor                 fun(state: S, ids: string[], active_id: string?, direction: LayoutDirection, workspace: WorkspaceContext, focus: boolean): string?
---@field on_focused_changed?      fun(state: S, ids: string[], active_id: string?)
---@field place                    fun(state: S, layout_context: HL.LayoutContext, targets: table<string, HL.LayoutTarget>, workspace: WorkspaceContext)

---@param strategy LayoutStrategy
---@param index integer
local function validate(strategy, index)
    local name = "strategies[" .. tostring(index) .. "]"
    assert(type(strategy) == "table", name .. " must be a table")
    for _, method in ipairs({
        "new_state",
        "place",
        "neighbor"
    }) do
        assert(type(strategy[method]) == "function", name .. "." .. method .. " must be a function")
    end
    assert(
        strategy.on_focused_changed == nil or type(strategy.on_focused_changed) == "function",
        name .. ".on_focused_changed must be a function"
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
