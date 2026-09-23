local util = require("dynamic_layout.framework.util")

local M = {}

M.name = "tall"

M.default = true
M.commands = { "tall" }
M.messages = { "tall", "ratio <0.1..0.9>", "grow", "shrink" }

function M.new_state()
    return { ratio = 0.5 }
end

function M.label(state)
    return util.ratio_label("TALL", state.ratio)
end

function M.restore_label(state, label)
    return util.restore_ratio_label(state, label, "TALL")
end

function M.focus_neighbor(_, ids, active_id, direction, context)
    return M.neighbor(ids, active_id, direction, context)
end

function M.focus_changed()
    -- This strategy has no navigation history.
end

function M.handle(state, command, arg, _, layout_context)
    return util.handle_ratio(state, command, arg, layout_context)
end

function M.neighbor(ids, active_id, direction, layout_context)
    local index = util.index_of(ids, active_id)
    if not index then return nil end

    local toward_stack = layout_context.reflect and "l" or "r"
    local toward_master = layout_context.reflect and "r" or "l"
    if index == 1 then
        return direction == toward_stack and ids[2] or nil
    elseif direction == toward_master then
        return ids[1]
    elseif direction == "u" then
        return index > 2 and ids[index - 1] or nil
    elseif direction == "d" then
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
        master:place(ctx:split(ctx.area, "right", state.ratio))
        util.place_stack(
            ctx, targets, { table.unpack(ids, 2) }, ctx:split(ctx.area, "left", 1 - state.ratio), "vertical"
        )
    else
        master:place(ctx:split(ctx.area, "left", state.ratio))
        util.place_stack(
            ctx, targets, { table.unpack(ids, 2) }, ctx:split(ctx.area, "right", 1 - state.ratio), "vertical"
        )
    end
end

return M
