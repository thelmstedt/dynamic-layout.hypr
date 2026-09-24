local M = {}

---@class LayoutContext
---@field active_id? string
---@field order      string[]
---@field reflect    boolean

function M.clamp(x, min, max)
    return math.max(min, math.min(max, x))
end

function M.set_ratio(state, ratio)
    state.ratio = M.clamp(ratio, 0.1, 0.9)
end

function M.resize_ratio(state, delta, context)
    local active_id, master_id = context.active_id, context.order[1]
    if active_id and master_id and active_id ~= master_id then delta = -delta end
    M.set_ratio(state, state.ratio + delta)
end

---@param name  string
---@param ratio number
---@return string
function M.ratio_label(name, ratio)
    return string.format("%s@%.3f", name, ratio)
end

---@param state { ratio: number }
---@param label string
---@param name  string
---@return boolean
function M.restore_ratio_label(state, label, name)
    if not label then
        return false
    end

    if label == name then
        return true
    end

    local ratio = label:match("^" .. name .. "@([%d.]+)$")
    if not ratio then
        return false
    end

    state.ratio = M.clamp(tonumber(ratio) or state.ratio, 0.1, 0.9)
    return true
end

---@param orientation "vertical" | "horizontal"
function M.place_stack(ctx, targets, ids, area, orientation)
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
                target:place(ctx:split(remaining_area, "top", 1 / remaining))
                remaining_area = ctx:split(remaining_area, "bottom", (remaining - 1) / remaining)
            else
                target:place(ctx:split(remaining_area, "left", 1 / remaining))
                remaining_area = ctx:split(remaining_area, "right", (remaining - 1) / remaining)
            end
        end

        remaining = remaining - 1
    end
end

function M.field(obj, key)
    local ok, value = pcall(function ()
        return obj and obj[key]
    end)

    if ok then
        return value
    end
end

function M.index_of(tbl, value)
    for i, v in ipairs(tbl) do
        if v == value then
            return i
        end
    end
end

return M
