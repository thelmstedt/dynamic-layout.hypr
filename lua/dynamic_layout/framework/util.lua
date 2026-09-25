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

---@param state { ratio: number }
---@param delta number
---@param workspace WorkspaceContext
function M.resize_ratio(state, delta, workspace)
    local active_id, master_id = workspace.active_id, workspace.order[1]
    if active_id and master_id and active_id ~= master_id then delta = -delta end
    M.set_ratio(state, state.ratio + delta)
end

---@param name  string
---@param ratio number?
---@return string
function M.ratio_label(name, ratio)
    if not ratio then return name end
    return string.format("%s@%.3f", name, ratio)
end

---@param state { ratio?: number }
---@param name  string
---@param label string?
---@return boolean
function M.restore_ratio_label(state, name, label)
    if not label then
        return false
    end

    if label == name then
        return true
    end

    local label_name, ratio = label:match("^(.-)@([%d.]+)$")
    if label_name ~= name or not ratio then
        return false
    end

    local current_ratio = state.ratio
    if current_ratio then
        state.ratio = M.clamp(tonumber(ratio) or current_ratio, 0.1, 0.9)
    end
    return true
end

---@param layout_context HL.LayoutContext
---@param targets table<string, HL.LayoutTarget>
---@param ids string[]
---@param area HL.Box
---@param orientation "vertical" | "horizontal"
function M.place_stack(layout_context, targets, ids, area, orientation)
    assert(
        orientation == "vertical" or orientation == "horizontal", "invalid stack orientation: " .. tostring(orientation)
    )
    local remaining_area = area
    local remaining = #ids

    for i, id in ipairs(ids) do
        local target = targets[id]
        if target then
            if i == #ids then
                target:place(remaining_area)
            elseif orientation == "vertical" then
                target:place(layout_context:split(remaining_area, "top", 1 / remaining))
                remaining_area = layout_context:split(remaining_area, "bottom", (remaining - 1) / remaining)
            else
                target:place(layout_context:split(remaining_area, "left", 1 / remaining))
                remaining_area = layout_context:split(remaining_area, "right", (remaining - 1) / remaining)
            end
        end

        remaining = remaining - 1
    end
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
