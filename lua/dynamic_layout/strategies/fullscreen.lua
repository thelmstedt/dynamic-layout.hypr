local util = require("dynamic_layout.framework.util")

local M = {}

M.name = "fullscreen"

M.commands = { "fullscreen", "full" }
M.messages = { "fullscreen", "full" }
M.needs_focus_recalculate = true

function M.new_state()
    return {}
end

function M.label()
    return "FULLSCREEN"
end

function M.restore_label(_, label)
    return label == "FULLSCREEN"
end

function M.neighbor(ids, active_id, direction)
    local index = util.index_of(ids, active_id)
    if not index then return nil end
    if direction == "l" or direction == "u" then return ids[index - 1] end
    if direction == "r" or direction == "d" then return ids[index + 1] end
end

function M.handle(_, command)
    if command == "focusactive" then
        return true
    end

    return false
end

function M.place(ctx, targets, ids, _, layout_context)
    local id = layout_context.active_id
    if not id or not targets[id] then
        id = ids[1]
    end

    for _, target_id_value in ipairs(ids) do
        local target = targets[target_id_value]
        if target and target_id_value ~= id then
            M.place_hidden(target, ctx.area)
        end
    end

    local active = targets[id]
    if active then
        active:place(ctx.area)
    end
end

-- The current Lua target API has no visibility setter so we just place it off screen
function M.place_hidden(target, area)
    target:place({ x = area.x - area.w - 100000, y = area.y, w = area.w, h = area.h })
end

return M
