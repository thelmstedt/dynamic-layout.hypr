local util = require("dynamic_layout.framework.util")

---@param index integer
---@return LayoutDirection
local function side_for_index(index)
    return index % 2 == 0 and "l" or "r"
end

-- The master spans the stack, so entering it preserves the last stack position.
---@param state CenteredStackState
---@param ids string[]
---@param active_id string?
local function on_focused_changed(state, ids, active_id)
    local index = util.index_of(ids, active_id)
    if index and index > 1 then state.focus_row = math.floor(index / 2) end
end

---@class CenteredStackState
---@field ratio     number
---@field focus_row number

---@class CenteredStackOptions
---@field ratio? number Master column's share of the area; defaults to 1/3.

-- Master centered, remaining windows alternating into left and right columns.
-- The only centered-stack implementation; mirror it for a horizontal variant.
---@param name string
---@param options? CenteredStackOptions
---@return LayoutStrategy<CenteredStackState>
return function (name, options)
    assert(type(name) == "string" and name ~= "", "centered-stack layout requires a name")
    options = options or {}
    local ratio = options.ratio or (1 / 3)
    assert(type(ratio) == "number" and ratio > 0 and ratio < 1, "ratio must be between 0 and 1")

    return {
        name = name,
        reflect_axis = "x",

        new_state = function ()
            return { ratio = ratio, focus_row = 1 }
        end,

        neighbor = function (state, direction, workspace, purpose)
            local ids = workspace.order
            local active_id = workspace.active_id
            local index = util.index_of(ids, active_id)
            if not index then return nil end

            if purpose == "focus" then on_focused_changed(state, ids, active_id) end
            if index == 1 then
                local neighbor
                for i = 2, #ids do
                    if side_for_index(i) == direction then
                        neighbor = ids[i]
                        if purpose ~= "focus" or math.floor(i / 2) >= state.focus_row then break end
                    end
                end
                return neighbor
            end

            local side = side_for_index(index)
            if direction == (side == "l" and "r" or "l") then return ids[1] end
            if direction ~= "u" and direction ~= "d" then return nil end

            local step = direction == "u" and -2 or 2
            local neighbor_index = index + step
            return neighbor_index >= 2 and ids[neighbor_index] or nil
        end,

        on_focused_changed = on_focused_changed,

        geometry = function (state, context, workspace)
            local ids = workspace.order
            local master_id = ids[1]
            if not master_id then return {} end
            if #ids == 1 then return { [master_id] = context.area } end

            local side_ratio = (1 - state.ratio) / 2
            if #ids == 2 then
                -- Share the whole area between the two occupied bands, keeping their
                -- relative weights so grow/shrink still works without an empty third.
                local master_ratio = state.ratio / (state.ratio + side_ratio)
                return {
                    [master_id] = context:split(context.area, "right", master_ratio),
                    [ids[2]] = context:split(context.area, "left", 1 - master_ratio),
                }
            end

            local first = context:split(context.area, "left", side_ratio)
            local last = context:split(context.area, "right", side_ratio)
            local middle = context:split(
                context:split(context.area, "right", 1 - side_ratio), "left", state.ratio / (state.ratio + side_ratio)
            )
            local first_stack, last_stack = {}, {}
            for i = 2, #ids do
                if (i % 2) == 0 then
                    table.insert(first_stack, ids[i])
                else
                    table.insert(last_stack, ids[i])
                end
            end

            ---@type table<string, HL.Box>
            local geometry = { [master_id] = middle }
            for id, box in pairs(util.stack_boxes(context, first_stack, first, "vertical")) do geometry[id] = box end
            for id, box in pairs(util.stack_boxes(context, last_stack, last, "vertical")) do geometry[id] = box end
            return geometry
        end,
    }
end
