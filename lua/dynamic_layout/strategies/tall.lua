local util = require("dynamic_layout.framework.util")

---@class MasterStackState
---@field ratio number

---@class MasterStackOptions
---@field ratio?   number  Master column's share of the area; defaults to 0.5.
---@field nmaster? integer Windows in the master column; defaults to 1.

-- Master column on the left holding the first `nmaster` windows, the rest stacked
-- on the right. The only master/stack implementation; mirror it for a horizontal
-- variant. Follows xmonad's Tall: with no stack, the masters fill the whole area.
---@param name string
---@param options? MasterStackOptions
---@return LayoutStrategy<MasterStackState>
return function (name, options)
    assert(type(name) == "string" and name ~= "", "master/stack layout requires a name")
    options = options or {}
    local ratio = options.ratio or 0.5
    local nmaster = options.nmaster or 1
    assert(type(ratio) == "number" and ratio > 0 and ratio < 1, "ratio must be between 0 and 1")
    assert(type(nmaster) == "number" and nmaster >= 1 and nmaster % 1 == 0, "nmaster must be a positive integer")

    return {
        name = name,
        reflect_axis = "x",

        new_state = function ()
            return { ratio = ratio }
        end,

        geometry = function (state, context, workspace)
            local ids = workspace.order
            local count = #ids
            if count == 0 then return {} end

            -- No stack: the master windows fill the whole area.
            if count <= nmaster then
                return util.stack_boxes(context, ids, context.area, "vertical")
            end

            local master_ids, stack_ids = {}, {}
            for i = 1, count do
                if i <= nmaster then
                    master_ids[#master_ids + 1] = ids[i]
                else
                    stack_ids[#stack_ids + 1] = ids[i]
                end
            end

            ---@type table<string, HL.Box>
            local geometry = {}
            local master_area = context:split(context.area, "left", state.ratio)
            local stack_area = context:split(context.area, "right", 1 - state.ratio)
            for id, box in pairs(util.stack_boxes(context, master_ids, master_area, "vertical")) do geometry[id] = box end
            for id, box in pairs(util.stack_boxes(context, stack_ids, stack_area, "vertical")) do geometry[id] = box end
            return geometry
        end,
    }
end
