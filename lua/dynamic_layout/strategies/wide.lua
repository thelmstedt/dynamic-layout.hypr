local util = require("dynamic_layout.framework.util")

local M = {}

M.name = "wide"

M.commands = { "wide" }
M.messages = { "wide", "ratio <0.1..0.9>", "grow", "shrink" }

function M.new_state()
    return { ratio = 0.5 }
end

function M.label(state)
    return util.ratio_label("WIDE", state.ratio)
end

function M.restore_label(state, label)
    return util.restore_ratio_label(state, label, "WIDE")
end

function M.handle(state, command, arg, _, layout_context)
    return util.handle_ratio(state, command, arg, layout_context)
end

function M.neighbor(ids, active_id, direction, layout_context)
    local index = util.index_of(ids, active_id)
    if not index then return nil end

    local toward_stack = layout_context.reflect and "u" or "d"
    local toward_master = layout_context.reflect and "d" or "u"
    if index == 1 then
        return direction == toward_stack and ids[2] or nil
    elseif direction == toward_master then
        return ids[1]
    elseif direction == "l" then
        return index > 2 and ids[index - 1] or nil
    elseif direction == "r" then
        return ids[index + 1]
    end
end

function M.place(ctx, targets, ids, state, layout_context)
    local master_id = ids[1]
    local master = targets[master_id]
    if not master then
        return
    end

    if #ids == 1 then
        master:place(ctx.area)
        return
    end

    local reflect = layout_context and layout_context.reflect
    if reflect then
        master:place(ctx:split(ctx.area, "bottom", state.ratio))
        util.place_stack(
            ctx, targets, { table.unpack(ids, 2) }, ctx:split(ctx.area, "top", 1 - state.ratio), "horizontal"
        )
    else
        master:place(ctx:split(ctx.area, "top", state.ratio))
        util.place_stack(
            ctx, targets, { table.unpack(ids, 2) }, ctx:split(ctx.area, "bottom", 1 - state.ratio), "horizontal"
        )
    end
end

return M
