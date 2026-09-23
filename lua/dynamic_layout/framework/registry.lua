local Registry = {}

---@class LayoutStrategy
---@field name                     string                                                                                                                   Stable strategy identifier.
---@field commands                 string[]                                                                                                                 Hyprland messages that select this strategy.
---@field messages                 string[]                                                                                                                 Human-readable strategy-specific messages.
---@field default?                 boolean                                                                                                                  Whether this is the initial strategy.
---@field needs_focus_recalculate? boolean                                                                                                                  Whether focus changes require placement.
---@field new_state                fun(): table
---@field label                    fun(state: table): string
---@field restore_label            fun(state: table, label: string?): boolean
---@field neighbor                 fun(ids: string[], active_id: string, direction: "l" | "r" | "u" | "d", context: LayoutContext): string?
---@field handle                   fun(state: table, command: string, arg: string, ctx: HL.LayoutContext, context: LayoutContext): boolean
---@field place                    fun(ctx: HL.LayoutContext, targets: table<string, HL.LayoutTarget>, ids: string[], state: table, context: LayoutContext)

local function validate(strategy, index)
    local name = "strategies[" .. tostring(index) .. "]"
    assert(type(strategy) == "table", name .. " must be a table")
    assert(type(strategy.commands) == "table", name .. ".commands must be a table")
    assert(type(strategy.messages) == "table", name .. ".messages must be a table")
    for _, method in ipairs({
        "new_state",
        "label",
        "restore_label",
        "place",
        "handle",
        "neighbor"
    }) do
        assert(type(strategy[method]) == "function", name .. "." .. method .. " must be a function")
    end
end

---@param strategies LayoutStrategy[]
---@return LayoutRegistry
function Registry.new(strategies)
    assert(type(strategies) == "table" and #strategies > 0, "at least one layout strategy is required")

    local instance = { layouts = strategies, commands = {}, by_name = {}, messages = {}, default_layout = nil }

    for index, strategy in ipairs(strategies) do
        validate(strategy, index)
        assert(type(strategy.name) == "string" and strategy.name ~= "", "strategy name is required")
        assert(not instance.by_name[strategy.name], "duplicate strategy name: " .. strategy.name)
        instance.by_name[strategy.name] = strategy
        if strategy.default then instance.default_layout = strategy end

        for _, command in ipairs(strategy.commands) do
            assert(instance.commands[command] == nil, "duplicate layout command: " .. command)
            instance.commands[command] = strategy
        end
        for _, message in ipairs(strategy.messages) do
            table.insert(instance.messages, message)
        end
    end

    instance.default_layout = instance.default_layout or strategies[1]
    return instance
end

---@class LayoutRegistry
---@field by_name        table<string, LayoutStrategy>
---@field layouts        LayoutStrategy[]
---@field commands       table<string, LayoutStrategy>
---@field messages       string[]
---@field default_layout LayoutStrategy

return Registry
