local util = require("dynamic_layout.framework.util")

local M = {}

M.name = "three_col"

M.commands = { "three_col" }
M.messages = { "three_col", "ratio <0.1..0.9>", "grow", "shrink" }

function M.new_state()
    return { ratio = 1 / 3, focus_row = 1 }
end

function M.label(state)
    return util.ratio_label("THREE_COL", state.ratio)
end

function M.restore_label(state, label)
    return util.restore_ratio_label(state, label, "THREE_COL")
end

local function side_for_index(index, reflect)
    local side = index % 2 == 0 and "l" or "r"
    if reflect then return side == "l" and "r" or "l" end
    return side
end

function M.neighbor(ids, active_id, direction, layout_context)
    local index = util.index_of(ids, active_id)
    if not index then return nil end

    if index == 1 then
        for i = 2, #ids do
            if side_for_index(i, layout_context.reflect) == direction then return ids[i] end
        end
        return nil
    end

    local side = side_for_index(index, layout_context.reflect)
    if direction == (side == "l" and "r" or "l") then return ids[1] end
    if direction ~= "u" and direction ~= "d" then return nil end

    local step = direction == "u" and -2 or 2
    local neighbor_index = index + step
    return neighbor_index >= 2 and ids[neighbor_index] or nil
end

-- The master spans every row, so entering it preserves the last side row.
function M.focus_changed(state, active_id, ids)
    local index = util.index_of(ids, active_id)
    if index and index > 1 then state.focus_row = math.floor(index / 2) end
end

function M.focus_neighbor(state, ids, active_id, direction, context)
    M.focus_changed(state, active_id, ids)
    if active_id ~= ids[1] then return M.neighbor(ids, active_id, direction, context) end

    local neighbor
    for i = 2, #ids do
        if side_for_index(i, context.reflect) == direction then
            neighbor = ids[i]
            if math.floor(i / 2) >= state.focus_row then break end
        end
    end
    return neighbor
end

function M.handle(state, command, arg, _, layout_context)
    return util.handle_ratio(state, command, arg, layout_context)
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

    local side_ratio = (1 - state.ratio) / 2
    local reflect = layout_context and layout_context.reflect
    if #ids == 2 then
        -- Share the whole area between the two occupied columns, keeping their
        -- relative weights so grow/shrink still works without an empty third.
        local master_ratio = state.ratio / (state.ratio + side_ratio)
        master:place(ctx:split(ctx.area, reflect and "left" or "right", master_ratio))
        targets[ids[2]]:place(ctx:split(ctx.area, reflect and "right" or "left", 1 - master_ratio))
        return
    end

    local left = ctx:split(ctx.area, "left", side_ratio)
    local right = ctx:split(ctx.area, "right", side_ratio)
    local middle = ctx:split(
        ctx:split(ctx.area, "right", 1 - side_ratio), "left", state.ratio / (state.ratio + side_ratio)
    )
    local left_stack = {}
    local right_stack = {}

    master:place(middle)

    for i = 2, #ids do
        local use_left = (i % 2) == 0
        if reflect then
            use_left = not use_left
        end

        if use_left then
            table.insert(left_stack, ids[i])
        else
            table.insert(right_stack, ids[i])
        end
    end

    util.place_stack(ctx, targets, left_stack, left, "vertical")
    util.place_stack(ctx, targets, right_stack, right, "vertical")
end

return M
