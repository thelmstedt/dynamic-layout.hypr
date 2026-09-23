local M = {}

---@class LayoutContext
---@field active_id? string
---@field order      string[]
---@field reflect    boolean

function M.clamp(x, min, max)
    return math.max(min, math.min(max, x))
end

---@param state           { ratio: number }
---@param command         string
---@param arg             string
---@param layout_context? LayoutContext
---@return boolean
function M.handle_ratio(state, command, arg, layout_context)
    if command == "ratio" then
        state.ratio = M.clamp(tonumber(arg) or state.ratio, 0.1, 0.9)
        return true
    end

    if command ~= "grow" and command ~= "shrink" then
        return false
    end

    local active_id = layout_context and layout_context.active_id
    local master_id = layout_context and layout_context.order[1]
    local focused_is_master = active_id == nil or master_id == nil or active_id == master_id
    local delta = command == "grow" and 0.03 or -0.03
    if not focused_is_master then
        delta = -delta
    end

    state.ratio = M.clamp(state.ratio + delta, 0.1, 0.9)
    return true
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
