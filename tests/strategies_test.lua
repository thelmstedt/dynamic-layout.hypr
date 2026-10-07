local a = require("tests.support.assertions")
local util = require("dynamic_layout.framework.util")
local geometric = require("dynamic_layout.framework.geometric")
local mirror = require("dynamic_layout.strategies.mirror")
local tall = require("dynamic_layout.strategies.tall")("tall")
local wide = mirror(tall, "wide")
local three_col = require("dynamic_layout.strategies.three_col")("three_col")

local function geometry_context()
    local layout_context = { area = { x = 10, y = 20, w = 1200, h = 600 } }
    function layout_context:split(area, side, ratio)
        local box = { x = area.x, y = area.y, w = area.w, h = area.h }
        if side == "left" or side == "right" then
            box.w = area.w * ratio
            if side == "right" then box.x = area.x + area.w - box.w end
        elseif side == "top" or side == "bottom" then
            box.h = area.h * ratio
            if side == "bottom" then box.y = area.y + area.h - box.h end
        else
            error("unexpected split side: " .. side)
        end
        return box
    end
    return layout_context
end

-- Reproduce what the engine does: ask the strategy for canonical geometry, then
-- mirror it when the workspace is reflected.
local function geometry_of(strategy, state, context, ids, reflect)
    local geometry = strategy.geometry(state, context, { order = ids, reflect = reflect })
    if reflect and strategy.reflect_axis then
        geometry = geometric.reflect(geometry, strategy.reflect_axis, context.area)
    end
    return geometry
end

return {
    ["three-row transposes geometry and navigation including reflection and focus history"] = function ()
        local rows = mirror(three_col, "three_row")
        local directions = { l = "u", r = "d", u = "l", d = "r" }
        for _, reflect in ipairs({ false, true }) do
            for count = 0, 7 do
                local columns_context, rows_context = geometry_context(), geometry_context()
                rows_context.area = { x = 20, y = 10, w = 600, h = 1200 }
                local ids = {}
                for i = 1, count do ids[i] = tostring(i) end
                local columns_state, rows_state = three_col.new_state(), rows.new_state()
                columns_state.ratio, rows_state.ratio = 0.6, 0.6
                local column_boxes = geometry_of(three_col, columns_state, columns_context, ids, reflect)
                local row_boxes = geometry_of(rows, rows_state, rows_context, ids, reflect)
                local workspace = { order = ids, reflect = reflect }
                local area = 0
                for _, id in ipairs(ids) do
                    local column, row = column_boxes[id], row_boxes[id]
                    a.box(row, { x = column.y, y = column.x, w = column.h, h = column.w })
                    area = area + row.w * row.h
                    workspace.active_id = id
                    for _, purpose in ipairs({ "focus", "swap" }) do
                        for direction, transposed in pairs(directions) do
                            a.equal(rows.neighbor(rows_state, transposed, workspace, purpose),
                                three_col.neighbor(columns_state, direction, workspace, purpose))
                        end
                    end
                    workspace.active_id = ids[1]
                    for direction, transposed in pairs(directions) do
                        a.equal(rows.neighbor(rows_state, transposed, workspace, "focus"),
                            three_col.neighbor(columns_state, direction, workspace, "focus"))
                    end
                end
                a.near(area, count == 0 and 0 or 720000)
            end
        end
    end,

    ["tall stacks children vertically on either side of the master"] = function ()
        for _, reflect in ipairs({ false, true }) do
            for _, count in ipairs({ 1, 2, 3, 4 }) do
                local ids = {}
                for i = 1, count do ids[i] = tostring(i) end
                local boxes = geometry_of(tall, { ratio = 0.6 }, geometry_context(), ids, reflect)
                local master = boxes["1"]
                a.near(master.x, count == 1 and 10 or (reflect and 490 or 10))
                a.near(master.y, 20)
                a.near(master.w, count == 1 and 1200 or 720)
                a.near(master.h, 600)
                for i = 2, count do
                    local child = boxes[tostring(i)]
                    a.near(child.x, reflect and 10 or 730)
                    a.near(child.y, 20 + (i - 2) * 600 / (count - 1))
                    a.near(child.w, 480)
                    a.near(child.h, 600 / (count - 1))
                end
            end
        end
    end,

    ["tall keeps the first nmaster windows in the master column"] = function ()
        local tall2 = require("dynamic_layout.strategies.tall")("tall", { nmaster = 2 })
        -- With no more than nmaster windows, they fill the whole area, no stack.
        local two = geometry_of(tall2, tall2.new_state(), geometry_context(), { "1", "2" }, false)
        a.box(two["1"], { x = 10, y = 20, w = 1200, h = 300 })
        a.box(two["2"], { x = 10, y = 320, w = 1200, h = 300 })
        -- A third window opens the stack column; both masters stay on the left.
        local state = tall2.new_state()
        state.ratio = 0.6
        local three = geometry_of(tall2, state, geometry_context(), { "1", "2", "3" }, false)
        a.box(three["1"], { x = 10, y = 20, w = 720, h = 300 })
        a.box(three["2"], { x = 10, y = 320, w = 720, h = 300 })
        a.box(three["3"], { x = 730, y = 20, w = 480, h = 600 })
    end,

    ["wide arranges children horizontally above or below the master"] = function ()
        for _, reflect in ipairs({ false, true }) do
            for _, count in ipairs({ 1, 2, 3, 4 }) do
                local ids = {}
                for i = 1, count do ids[i] = tostring(i) end
                local boxes = geometry_of(wide, { ratio = 0.6 }, geometry_context(), ids, reflect)
                local master = boxes["1"]
                a.near(master.x, 10)
                a.near(master.y, count == 1 and 20 or (reflect and 260 or 20))
                a.near(master.w, 1200)
                a.near(master.h, count == 1 and 600 or 360)
                for i = 2, count do
                    local child = boxes[tostring(i)]
                    a.near(child.x, 10 + (i - 2) * 1200 / (count - 1))
                    a.near(child.y, reflect and 20 or 380)
                    a.near(child.w, 1200 / (count - 1))
                    a.near(child.h, 240)
                end
            end
        end
    end,

    ["grow and shrink resize the master regardless of focus"] = function ()
        local state = { ratio = 0.5 }
        util.resize_ratio(state, 0.03)
        a.near(state.ratio, 0.53)
        util.resize_ratio(state, 0.03)
        a.near(state.ratio, 0.56)
        util.resize_ratio(state, -0.03)
        a.near(state.ratio, 0.53)
    end,

    -- tall defines no neighbor; the framework derives navigation from the boxes
    -- the strategy placed. At up to three windows this matches the former
    -- hand-written master/stack navigation exactly.
    ["tall navigation follows master and stack geometry via the framework"] = function ()
        local ids = { "a", "b", "c" }
        local boxes = geometry_of(tall, { ratio = 0.5 }, geometry_context(), ids, false)
        a.equal(geometric.nearest(boxes, ids, "a", "r"), "b")
        a.equal(geometric.nearest(boxes, ids, "c", "u"), "b")
        a.equal(geometric.nearest(boxes, ids, "b", "l"), "a")
    end,

    -- Navigation is canonical: the strategy never consults reflect. The engine
    -- mirrors the direction instead, which the next test covers.
    ["three-column neighbors follow master and side columns"] = function ()
        local ids = { "master", "left1", "right1", "left2", "right2" }
        a.equal(three_col.neighbor(three_col.new_state(), "l", { active_id = "master", order = ids, reflect = false }), "left1")
        a.equal(three_col.neighbor(three_col.new_state(), "r", { active_id = "master", order = ids, reflect = false }), "right1")
        a.equal(three_col.neighbor(three_col.new_state(), "d", { active_id = "left1", order = ids, reflect = false }), "left2")
        local workspace = { active_id = "left1", order = ids, reflect = false }
        a.equal(three_col.neighbor(three_col.new_state(), "u", workspace), nil)
        workspace.active_id = "right1"
        a.equal(three_col.neighbor(three_col.new_state(), "u", workspace), nil)
        workspace.active_id = "right2"
        a.equal(three_col.neighbor(three_col.new_state(), "u", workspace), "right1")
        a.equal(three_col.neighbor(three_col.new_state(), "d", workspace), nil)
    end,

    ["reflection mirrors navigation direction, not the strategy"] = function ()
        a.equal(geometric.flip("l", "x"), "r")
        a.equal(geometric.flip("r", "x"), "l")
        a.equal(geometric.flip("u", "x"), "u")
        a.equal(geometric.flip("u", "y"), "d")
        a.equal(geometric.flip("l", "y"), "l")
        -- The engine flips before calling neighbor, so under horizontal reflection
        -- a "left" keypress selects the window a canonical "right" would.
        local ids = { "master", "left1", "right1" }
        a.equal(
            three_col.neighbor(three_col.new_state(), geometric.flip("l", "x"), { active_id = "master", order = ids, reflect = false }),
            "right1"
        )
    end,

    ["three-column tracks its row independently of swaps and other workspaces"] = function ()
        local ids = { "master", "left1", "right1", "left2", "right2" }
        local state, other = three_col.new_state(), three_col.new_state()
        a.equal(three_col.neighbor(state, "r", { active_id = "left2", order = ids, reflect = false }, "focus"), "master")
        three_col.on_focused_changed(state, ids, "master")
        a.equal(three_col.neighbor(state, "r", { active_id = "master", order = ids, reflect = false }, "swap"), "right1")
        a.equal(three_col.neighbor(other, "r", { active_id = "master", order = ids, reflect = false }, "focus"), "right1")
        a.equal(three_col.neighbor(state, "r", { active_id = "master", order = ids, reflect = false }, "focus"), "right2")
        local short = { "master", "left1", "right1", "left2" }
        a.equal(three_col.neighbor(state, "r", { active_id = "left2", order = short, reflect = false }, "focus"), "master")
        a.equal(three_col.neighbor(state, "r", { active_id = "master", order = short, reflect = false }, "focus"), "right1")
        three_col.neighbor(state, "r", { active_id = "left2", order = ids, reflect = false }, "focus")
        three_col.on_focused_changed(state, ids, "left1")
        a.equal(three_col.neighbor(state, "r", { active_id = "master", order = ids, reflect = false }, "focus"), "right1")
    end,

    ["three-column fills the area as windows are added and removed"] = function ()
        local layout_context = { area = { x = 10, y = 20, w = 1200, h = 600 } }
        function layout_context:split(area, side, ratio)
            assert(side == "left" or side == "right")
            return {
                x = area.x + (side == "right" and area.w * (1 - ratio) or 0),
                y = area.y,
                w = area.w * ratio,
                h = area.h
            }
        end
        for _, reflect in ipairs({ false, true }) do
            local state = three_col.new_state()
            for _, count in ipairs({ 1, 2, 3, 2, 1 }) do
                local ids = {}
                for i = 1, count do ids[i] = tostring(i) end
                local boxes = geometry_of(three_col, state, layout_context, ids, reflect)
                local ordered = {}
                for _, id in ipairs(ids) do
                    local box = assert(boxes[id])
                    a.near(box.w, layout_context.area.w / count)
                    a.near(box.h, layout_context.area.h)
                    a.near(box.y, layout_context.area.y)
                    ordered[#ordered + 1] = box
                end
                table.sort(ordered, function (left, right) return left.x < right.x end)
                local edge = layout_context.area.x
                for _, box in ipairs(ordered) do
                    a.near(box.x, edge)
                    edge = edge + box.w
                end
                a.near(edge, layout_context.area.x + layout_context.area.w)
                if count == 2 then
                    a.near(boxes["1"].x, reflect and 10 or 610)
                    a.equal(three_col.neighbor(three_col.new_state(), "l", { active_id = "1", order = ids, reflect = false }, "swap"), "2")
                end
            end
        end
    end
}
