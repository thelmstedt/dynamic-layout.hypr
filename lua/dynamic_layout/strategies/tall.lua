local util = require("dynamic_layout.framework.util")

---@class TallState
---@field ratio number

---@type LayoutStrategy<TallState>
local strategy = {
    name = "tall",

    new_state = function ()
        return { ratio = 0.5 }
    end,

    neighbor = function (_, ids, active_id, direction, workspace)
        local index = util.index_of(ids, active_id)
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

        local reflect = workspace.reflect
        if reflect then
            master:place(layout_context:split(layout_context.area, "right", state.ratio))
            util.place_stack(
                layout_context, targets, { table.unpack(ids, 2) }, layout_context:split(layout_context.area, "left", 1 - state.ratio), "vertical"
            )
        else
            master:place(layout_context:split(layout_context.area, "left", state.ratio))
            util.place_stack(
                layout_context, targets, { table.unpack(ids, 2) }, layout_context:split(layout_context.area, "right", 1 - state.ratio), "vertical"
            )
        end
    end,
}

return strategy
