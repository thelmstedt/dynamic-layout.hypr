-- Framework-owned geometry transforms. Strategies return canonical (unreflected)
-- boxes from `geometry`; the engine applies reflection here and derives
-- directional navigation here, so most strategies need neither reflect branches
-- nor a hand-written `neighbor`.
---@class GeometricModule
local M = {}

---@param box HL.Box
---@param axis "x"|"y"
---@param area HL.Box
---@return HL.Box
local function mirror(box, axis, area)
    if axis == "x" then
        return { x = area.x + area.x + area.w - box.x - box.w, y = box.y, w = box.w, h = box.h }
    end
    return { x = box.x, y = area.y + area.y + area.h - box.y - box.h, w = box.w, h = box.h }
end

--- Reflect a box across the main diagonal, swapping x/y and w/h. Applying this
--- to an area, laying out within it, and reflecting each result box back is
--- xmonad's `Mirror`: it turns a horizontal layout into a vertical one.
---@param box HL.Box
---@return HL.Box
function M.mirror_rect(box)
    return { x = box.y, y = box.x, w = box.h, h = box.w }
end

--- Mirror a direction across the given axis: horizontal reflection swaps
--- left/right, vertical swaps up/down. Other directions pass through.
---@param direction LayoutDirection
---@param axis "x"|"y"
---@return LayoutDirection
function M.flip(direction, axis)
    if axis == "x" then
        if direction == "l" then return "r" end
        if direction == "r" then return "l" end
    else
        if direction == "u" then return "d" end
        if direction == "d" then return "u" end
    end
    return direction
end

--- Mirror every box across the given axis within `area`.
---@param geometry table<string, HL.Box>
---@param axis "x"|"y"
---@param area HL.Box
---@return table<string, HL.Box>
function M.reflect(geometry, axis, area)
    ---@type table<string, HL.Box>
    local mirrored = {}
    for id, box in pairs(geometry) do mirrored[id] = mirror(box, axis, area) end
    return mirrored
end

--- Nearest tile across the shared edge in `direction`, breaking ties by the
--- smaller center offset and then by workspace order.
---@param geometry table<string, HL.Box>
---@param order string[]
---@param active_id string?
---@param direction LayoutDirection
---@return string?
function M.nearest(geometry, order, active_id, direction)
    local origin = active_id and geometry[active_id]
    if not origin then return nil end
    local horizontal = direction == "l" or direction == "r"
    if not horizontal and direction ~= "u" and direction ~= "d" then return nil end
    local best, distance
    for _, id in ipairs(order) do
        local box = geometry[id]
        if id ~= active_id and box then
            local gap, overlap, offset
            if horizontal then
                gap = direction == "l" and origin.x - box.x - box.w or box.x - origin.x - origin.w
                overlap = math.min(origin.y + origin.h, box.y + box.h) - math.max(origin.y, box.y)
                offset = math.abs(origin.y + origin.h / 2 - box.y - box.h / 2)
            else
                gap = direction == "u" and origin.y - box.y - box.h or box.y - origin.y - origin.h
                overlap = math.min(origin.x + origin.w, box.x + box.w) - math.max(origin.x, box.x)
                offset = math.abs(origin.x + origin.w / 2 - box.x - box.w / 2)
            end
            if math.abs(gap) < 0.000001 and overlap > 0 and (not distance or offset < distance) then
                best, distance = id, offset
            end
        end
    end
    return best
end

return M
