local util = require("dynamic_layout.framework.util")

---@class FullscreenState

---@type LayoutStrategy<FullscreenState>
local strategy = {
    name = "fullscreen",
    needs_focus_recalculate = true,

    new_state = function ()
        return {}
    end,

    neighbor = function (_, ids, active_id, direction)
        local index = util.index_of(ids, active_id)
        if not index then return nil end
        if direction == "l" or direction == "u" then return ids[index - 1] end
        if direction == "r" or direction == "d" then return ids[index + 1] end
    end,

    place = function (_, layout_context, targets, workspace)
        local ids = workspace.order
        local id = workspace.active_id
        if not id or not targets[id] then
            id = ids[1]
        end

        for _, target_id in ipairs(ids) do
            local target = targets[target_id]
            if target and target_id ~= id then
                -- Hyprland has no visibility setter; place inactive windows off screen.
                target:place({
                    x = layout_context.area.x - layout_context.area.w - 100000,
                    y = layout_context.area.y,
                    w = layout_context.area.w,
                    h = layout_context.area.h
                })
            end
        end

        local active = targets[id]
        if active then
            active:place(layout_context.area)
        end
    end
}

return strategy
