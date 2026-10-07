---@class LayoutUtilModule
local M = {}

---@alias LayoutDirection "l" | "r" | "u" | "d"

---@class WorkspaceContext
---@field active_id? string
---@field order      string[]
---@field reflect    boolean

---@param x number
---@param min number
---@param max number
---@return number
function M.clamp(x, min, max)
    return math.max(min, math.min(max, x))
end

---@param state { ratio?: number }
---@param ratio number
function M.set_ratio(state, ratio)
    state.ratio = M.clamp(ratio, 0.1, 0.9)
end

-- Master-relative, like xmonad's Expand/Shrink: grow always enlarges the master
-- and shrink always shrinks it, regardless of which window is focused.
---@param state { ratio: number }
---@param delta number
function M.resize_ratio(state, delta)
    M.set_ratio(state, state.ratio + delta)
end

---@param box HL.Box
---@param side 'left'|'right'|'top'|'bottom'
---@param ratio number
---@return HL.Box
function M.split(box, side, ratio)
    local result = { x = box.x, y = box.y, w = box.w, h = box.h }
    if side == "left" or side == "right" then
        result.w = box.w * ratio
        if side == "right" then result.x = box.x + box.w - result.w end
    elseif side == "top" or side == "bottom" then
        result.h = box.h * ratio
        if side == "bottom" then result.y = box.y + box.h - result.h end
    else
        error("invalid split side: " .. tostring(side))
    end
    return result
end

-- A pure-Lua layout context. Strategies compute the same geometry whether
-- Hyprland is driving a placement or the framework is deriving navigation
-- between placements, where Hyprland's own context is not available. Gaps are a
-- render-time concern Hyprland applies when a box is placed, so plain
-- subdivision here matches what its context would return.
---@param area HL.Box
---@return HL.LayoutContext
function M.context(area)
    ---@diagnostic disable-next-line: missing-fields
    return { area = area, split = function (_, box, side, ratio) return M.split(box, side, ratio) end }
end

-- Returns an id -> box map without touching targets, so strategies can hand
-- their geometry back to the framework for placement and navigation.
---@param layout_context HL.LayoutContext
---@param ids string[]
---@param area HL.Box
---@param orientation "vertical" | "horizontal"
---@param start_index? integer
---@return table<string, HL.Box>
function M.stack_boxes(layout_context, ids, area, orientation, start_index)
    assert(
        orientation == "vertical" or orientation == "horizontal", "invalid stack orientation: " .. tostring(orientation)
    )
    start_index = start_index or 1
    local total = #ids
    ---@type table<string, HL.Box>
    local boxes = {}
    local remaining = total - start_index + 1
    if remaining <= 0 then return boxes end
    local remaining_area = area

    for i = start_index, total do
        local id = ids[i]
        if i == total then
            boxes[id] = remaining_area
        elseif orientation == "vertical" then
            boxes[id] = layout_context:split(remaining_area, "top", 1 / remaining)
            remaining_area = layout_context:split(remaining_area, "bottom", (remaining - 1) / remaining)
        else
            boxes[id] = layout_context:split(remaining_area, "left", 1 / remaining)
            remaining_area = layout_context:split(remaining_area, "right", (remaining - 1) / remaining)
        end
        remaining = remaining - 1
    end
    return boxes
end

-- Runtime boundary for fields on Hyprland objects whose access may throw.
-- The key is dynamic, so the result cannot have a more specific static type.
---@param obj any
---@param key string
---@return any
function M.field(obj, key)
    local ok, value = pcall(function ()
        return obj and obj[key]
    end)

    if ok then
        return value
    end
end

---@generic T
---@param tbl T[]
---@param value T?
---@return integer?
function M.index_of(tbl, value)
    for i, v in ipairs(tbl) do
        if v == value then
            return i
        end
    end
end

return M
