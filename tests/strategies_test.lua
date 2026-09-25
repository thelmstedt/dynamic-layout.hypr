local a = require("tests.support.assertions")
local util = require("dynamic_layout.framework.util")
local tall = require("dynamic_layout.strategies.tall")
local wide = require("dynamic_layout.strategies.wide")
local three_col = require("dynamic_layout.strategies.three_col")

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

return {
    ["tall stacks children vertically on either side of the master"] = function ()
        local layout_context = geometry_context()
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
                tall.place({ ratio = 0.6 }, layout_context, targets, { order = ids, reflect = reflect })
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
        local layout_context = geometry_context()
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
                wide.place({ ratio = 0.6 }, layout_context, targets, { order = ids, reflect = reflect })
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
        local workspace = { active_id = "master", order = { "master", "stack" }, reflect = false }
        util.resize_ratio(state, 0.03, workspace)
        a.near(state.ratio, 0.53)
        workspace.active_id = "stack"
        util.resize_ratio(state, 0.03, workspace)
        a.near(state.ratio, 0.5)
        util.resize_ratio(state, -0.03, workspace)
        a.near(state.ratio, 0.53)
    end,

    ["tall neighbors follow master and stack geometry"] = function ()
        local ids = { "a", "b", "c" }
        a.equal(tall.neighbor(tall.new_state(), "r", { active_id = "a", order = ids, reflect = false }), "b")
        a.equal(tall.neighbor(tall.new_state(), "u", { active_id = "c", order = ids, reflect = false }), "b")
        a.equal(tall.neighbor(tall.new_state(), "l", { active_id = "b", order = ids, reflect = false }), "a")
    end,

    ["three-column neighbors respect reflection and boundaries"] = function ()
        local ids = { "master", "left1", "right1", "left2", "right2" }
        a.equal(three_col.neighbor(three_col.new_state(), "l", { active_id = "master", order = ids, reflect = false }), "left1")
        a.equal(three_col.neighbor(three_col.new_state(), "r", { active_id = "master", order = ids, reflect = false }), "right1")
        a.equal(three_col.neighbor(three_col.new_state(), "d", { active_id = "left1", order = ids, reflect = false }), "left2")
        a.equal(three_col.neighbor(three_col.new_state(), "l", { active_id = "master", order = ids, reflect = true }), "right1")
        for _, reflect in ipairs({ false, true }) do
            local workspace = { active_id = "left1", order = ids, reflect = reflect }
            a.equal(three_col.neighbor(three_col.new_state(), "u", workspace), nil)
            workspace.active_id = "right1"
            a.equal(three_col.neighbor(three_col.new_state(), "u", workspace), nil)
            workspace.active_id = "right2"
            a.equal(three_col.neighbor(three_col.new_state(), "u", workspace), "right1")
            a.equal(three_col.neighbor(three_col.new_state(), "d", workspace), nil)
        end
    end,

    ["three-column tracks its row independently of swaps and other workspaces"] = function ()
        local ids = { "master", "left1", "right1", "left2", "right2" }
        local state, other = three_col.new_state(), three_col.new_state()
        a.equal(three_col.neighbor(state, "r", { active_id = "left2", order = ids, reflect = false }, true), "master")
        three_col.on_focused_changed(state, ids, "master")
        a.equal(three_col.neighbor(state, "r", { active_id = "master", order = ids, reflect = false }, false), "right1")
        a.equal(three_col.neighbor(other, "r", { active_id = "master", order = ids, reflect = false }, true), "right1")
        a.equal(three_col.neighbor(state, "r", { active_id = "master", order = ids, reflect = false }, true), "right2")
        local short = { "master", "left1", "right1", "left2" }
        a.equal(three_col.neighbor(state, "r", { active_id = "left2", order = short, reflect = false }, true), "master")
        a.equal(three_col.neighbor(state, "r", { active_id = "master", order = short, reflect = false }, true), "right1")
        three_col.neighbor(state, "r", { active_id = "left2", order = ids, reflect = false }, true)
        three_col.on_focused_changed(state, ids, "left1")
        a.equal(three_col.neighbor(state, "r", { active_id = "master", order = ids, reflect = false }, true), "right1")
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
                three_col.place(state, layout_context, targets, { order = ids, reflect = reflect })
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
                    a.equal(three_col.neighbor(three_col.new_state(), reflect and "r" or "l", { active_id = "1", order = ids, reflect = reflect }, false), "2")
                end
            end
        end
    end
}
