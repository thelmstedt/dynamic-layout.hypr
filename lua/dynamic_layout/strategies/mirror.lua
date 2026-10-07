local geometric = require("dynamic_layout.framework.geometric")

-- Directions reflected across the main diagonal: horizontal <-> vertical.
local DIAGONAL = { l = "u", r = "d", u = "l", d = "r" }

-- xmonad's `Mirror` as a strategy modifier: run `base` with width and height
-- swapped, then swap the resulting boxes and navigation back, turning a
-- horizontal layout into a vertical one. `wide` is mirror(`tall`); `three_row`
-- is mirror(`three_col`), so each master/stack shape is written only once.
---@param base LayoutStrategy<any>
---@param name string
---@return LayoutStrategy<any>
return function (base, name)
    ---@type LayoutStrategy<any>
    local strategy = {
        name = name,
        new_state = base.new_state,
        on_focused_changed = base.on_focused_changed,
        single_window = base.single_window,
        needs_focus_recalculate = base.needs_focus_recalculate,
        -- Reflection mirrors across the base's axis, swapped with everything else.
        reflect_axis = base.reflect_axis == "x" and "y" or base.reflect_axis == "y" and "x" or nil,

        geometry = function (state, context, workspace)
            local mirrored = { area = geometric.mirror_rect(context.area), split = context.split }
            ---@type table<string, HL.Box>
            local result = {}
            for id, box in pairs(base.geometry(state, mirrored, workspace)) do
                result[id] = geometric.mirror_rect(box)
            end
            return result
        end,
    }

    if base.neighbor then
        strategy.neighbor = function (state, direction, workspace, purpose)
            return base.neighbor(state, DIAGONAL[direction], workspace, purpose)
        end
    end

    return strategy
end
