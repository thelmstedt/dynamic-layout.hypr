local util = require("dynamic_layout.framework.util")

---@class TallState
---@field ratio number

---@type LayoutStrategy<TallState>
local strategy = {
    name = "tall",

    new_state = function ()
        return { ratio = 0.5 }
    end,

    neighbor = function (_, direction, workspace)
        local ids = workspace.order
        local index = util.index_of(ids, workspace.active_id)
        if not index then return nil end

        local toward_stack = workspace.reflect and "l" or "r"
        local toward_master = workspace.reflect and "r" or "l"
        if index == 1 then
            return direction == toward_stack and ids[2] or nil
        elseif direction == toward_master then
            return ids[1]
        elseif direction == "u" then
            return index > 2 and ids[index - 1] or nil
        elseif direction == "d" then
            return ids[index + 1]
        end
    end,

    place = function (state, layout_context, targets, workspace)
        local ids = workspace.order
        local master_id = ids[1]
        local master = targets[master_id]
        if not master then
            return
        end

        if #ids == 1 then
            master:place(layout_context.area)
            return
        end

        local master_side = workspace.reflect and "right" or "left"
        local stack_side = workspace.reflect and "left" or "right"
        master:place(layout_context:split(layout_context.area, master_side, state.ratio))
        util.place_stack(
            layout_context, targets, ids, layout_context:split(layout_context.area, stack_side, 1 - state.ratio), "vertical", 2
        )
    end,
}

return strategy
