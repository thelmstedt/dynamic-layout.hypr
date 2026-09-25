local util = require("dynamic_layout.framework.util")

---@class WideState
---@field ratio number

---@type LayoutStrategy<WideState>
local strategy = {
    name = "wide",

    new_state = function ()
        return { ratio = 0.5 }
    end,

    neighbor = function (_, ids, active_id, direction, workspace)
        local index = util.index_of(ids, active_id)
        if not index then return nil end

        local toward_stack = workspace.reflect and "u" or "d"
        local toward_master = workspace.reflect and "d" or "u"
        if index == 1 then
            return direction == toward_stack and ids[2] or nil
        elseif direction == toward_master then
            return ids[1]
        elseif direction == "l" then
            return index > 2 and ids[index - 1] or nil
        elseif direction == "r" then
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
            master:place(layout_context:split(layout_context.area, "bottom", state.ratio))
            util.place_stack(
                layout_context, targets, { table.unpack(ids, 2) }, layout_context:split(layout_context.area, "top", 1 - state.ratio), "horizontal"
            )
        else
            master:place(layout_context:split(layout_context.area, "top", state.ratio))
            util.place_stack(
                layout_context, targets, { table.unpack(ids, 2) }, layout_context:split(layout_context.area, "bottom", 1 - state.ratio), "horizontal"
            )
        end
    end
}

return strategy
