local util = require("dynamic_layout.framework.util")

---@class FullscreenState

-- Only the active window is visible; the rest are parked off screen.
---@param name string
---@return LayoutStrategy<FullscreenState>
return function (name)
    assert(type(name) == "string" and name ~= "", "fullscreen layout requires a name")
    return {
        name = name,
        single_window = true,
        needs_focus_recalculate = true,

        new_state = function ()
            return {}
        end,

        neighbor = function (_, direction, workspace)
            local ids = workspace.order
            local index = util.index_of(ids, workspace.active_id)
            if not index then return nil end
            if direction == "l" or direction == "u" then return ids[index - 1] end
            if direction == "r" or direction == "d" then return ids[index + 1] end
        end,

        geometry = function (_, context, workspace)
            local ids = workspace.order
            local id = workspace.active_id
            if not id or not util.index_of(ids, id) then
                id = ids[1]
            end

            -- Hyprland has no visibility setter; place inactive windows off screen.
            local offscreen = {
                x = context.area.x - context.area.w - 100000,
                y = context.area.y,
                w = context.area.w,
                h = context.area.h
            }
            ---@type table<string, HL.Box>
            local geometry = {}
            for _, target_id in ipairs(ids) do
                geometry[target_id] = target_id == id and context.area or offscreen
            end
            return geometry
        end,
    }
end
