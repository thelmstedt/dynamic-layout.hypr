local a = require("tests.support.assertions")
local util = require("dynamic_layout.framework.util")
local tall = require("dynamic_layout.strategies.tall")
local wide = require("dynamic_layout.strategies.wide")
local three_col = require("dynamic_layout.strategies.three_col")

local function geometry_context()
    local ctx = { area = { x = 10, y = 20, w = 1200, h = 600 } }
    function ctx:split(area, side, ratio)
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
    return ctx
end

return {
    ["tall stacks children vertically on either side of the master"] = function ()
        local ctx = geometry_context()
        for _, reflect in ipairs({ false, true }) do
            for _, count in ipairs({ 1, 2, 3, 4 }) do
                local ids, targets, boxes = {}, {}, {}
                for i = 1, count do
                    local id = tostring(i)
                    ids[i] = id
                    targets[id] = {
                        place = function (_, box)
                            boxes[id] = box
                        end
                    }
                end
                tall.place(ctx, targets, ids, { ratio = 0.6 }, { reflect = reflect })
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

    ["wide arranges children horizontally above or below the master"] = function ()
        local ctx = geometry_context()
        for _, reflect in ipairs({ false, true }) do
            for _, count in ipairs({ 1, 2, 3, 4 }) do
                local ids, targets, boxes = {}, {}, {}
                for i = 1, count do
                    local id = tostring(i)
                    ids[i] = id
                    targets[id] = {
                        place = function (_, box)
                            boxes[id] = box
                        end
                    }
                end
                wide.place(ctx, targets, ids, { ratio = 0.6 }, { reflect = reflect })
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

    ["grow and shrink resize the focused side"] = function ()
        local state = { ratio = 0.5 }
        local context = { active_id = "master", order = { "master", "stack" }, reflect = false }
        util.resize_ratio(state, 0.03, context)
        a.near(state.ratio, 0.53)
        context.active_id = "stack"
        util.resize_ratio(state, 0.03, context)
        a.near(state.ratio, 0.5)
        util.resize_ratio(state, -0.03, context)
        a.near(state.ratio, 0.53)
    end,

    ["tall ratio labels round trip"] = function ()
        local state = tall.new_state()
        state.ratio = 0.637
        a.equal(tall.label(state), "TALL@0.637")
        local restored = tall.new_state()
        a.equal(tall.restore_label(restored, tall.label(state)), true)
        a.equal(restored.ratio, 0.637)
    end,

    ["tall neighbors follow master and stack geometry"] = function ()
        local ids, context = { "a", "b", "c" }, { reflect = false }
        a.equal(tall.neighbor(ids, "a", "r", context), "b")
        a.equal(tall.neighbor(ids, "c", "u", context), "b")
        a.equal(tall.neighbor(ids, "b", "l", context), "a")
    end,

    ["three-column neighbors respect reflection and boundaries"] = function ()
        local ids = { "master", "left1", "right1", "left2", "right2" }
        a.equal(three_col.neighbor(ids, "master", "l", { reflect = false }), "left1")
        a.equal(three_col.neighbor(ids, "master", "r", { reflect = false }), "right1")
        a.equal(three_col.neighbor(ids, "left1", "d", { reflect = false }), "left2")
        a.equal(three_col.neighbor(ids, "master", "l", { reflect = true }), "right1")
        for _, reflect in ipairs({ false, true }) do
            local context = { reflect = reflect }
            a.equal(three_col.neighbor(ids, "left1", "u", context), nil)
            a.equal(three_col.neighbor(ids, "right1", "u", context), nil)
            a.equal(three_col.neighbor(ids, "right2", "u", context), "right1")
            a.equal(three_col.neighbor(ids, "right2", "d", context), nil)
        end
    end,

    ["three-column tracks its row independently of swaps and other workspaces"] = function ()
        local ids = { "master", "left1", "right1", "left2", "right2" }
        local state, other = three_col.new_state(), three_col.new_state()
        local context = { reflect = false }
        a.equal(three_col.focus_neighbor(state, ids, "left2", "r", context), "master")
        three_col.focus_changed(state, "master", ids)
        a.equal(three_col.neighbor(ids, "master", "r", context), "right1")
        a.equal(three_col.focus_neighbor(other, ids, "master", "r", context), "right1")
        a.equal(three_col.focus_neighbor(state, ids, "master", "r", context), "right2")
        local short = { "master", "left1", "right1", "left2" }
        a.equal(three_col.focus_neighbor(state, short, "left2", "r", context), "master")
        a.equal(three_col.focus_neighbor(state, short, "master", "r", context), "right1")
        three_col.focus_neighbor(state, ids, "left2", "r", context)
        three_col.focus_changed(state, "left1", ids)
        a.equal(three_col.focus_neighbor(state, ids, "master", "r", context), "right1")
    end,

    ["three-column fills the area as windows are added and removed"] = function ()
        local ctx = { area = { x = 10, y = 20, w = 1200, h = 600 } }
        function ctx:split(area, side, ratio)
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
                local ids, targets, boxes = {}, {}, {}
                for i = 1, count do
                    local id = tostring(i)
                    ids[i] = id
                    targets[id] = {
                        place = function (_, box)
                            boxes[id] = box
                        end
                    }
                end
                three_col.place(ctx, targets, ids, state, { reflect = reflect })
                local ordered = {}
                for _, id in ipairs(ids) do
                    local box = assert(boxes[id])
                    a.near(box.w, ctx.area.w / count)
                    a.near(box.h, ctx.area.h)
                    a.near(box.y, ctx.area.y)
                    ordered[#ordered + 1] = box
                end
                table.sort(ordered, function (left, right) return left.x < right.x end)
                local edge = ctx.area.x
                for _, box in ipairs(ordered) do
                    a.near(box.x, edge)
                    edge = edge + box.w
                end
                a.near(edge, ctx.area.x + ctx.area.w)
                if count == 2 then
                    a.near(boxes["1"].x, reflect and 10 or 610)
                    a.equal(three_col.neighbor(ids, "1", reflect and "r" or "l", { reflect = reflect }), "2")
                end
            end
        end
    end
}
