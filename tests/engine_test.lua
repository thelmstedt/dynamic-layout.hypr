local a = require("tests.support.assertions")
local fixture = require("tests.support.fixtures")
local Store = require("dynamic_layout.framework.store")
local Persistence = require("dynamic_layout.framework.persistence")

return {
    ["fullscreen retains selection when workspace loses focus"] = function ()
        local env = fixture.engine()
        a.equal(env.registered.dynamic, env.controller.definition)
        a.equal(Store.layout_label(env.ws), "FULLSCREEN")
        a.equal(env.boxes[2], env.empty.area)
        assert(env.boxes[1].x < 0 and env.boxes[3].x < 0)
        fixture.focus(env, nil)
        env.controller.definition.recalculate(env.context)
        a.equal(env.boxes[2], env.empty.area)
    end,

    ["focus hooks select fullscreen windows and ignore floating focus"] = function ()
        local env = fixture.engine()
        fixture.focus(env, 3)
        a.equal(env.ws.selected_id, "3")
        a.equal(env.dispatched[#env.dispatched], "focusactive")
        env.controller.definition.recalculate(env.context)
        a.equal(env.boxes[3], env.empty.area)
        local before = #env.dispatched
        env.windows[1].floating = true
        fixture.focus(env, 1)
        a.equal(env.ws.selected_id, "3")
        a.equal(#env.dispatched, before)
    end,

    ["focus cycles in order with wrapping"] = function ()
        local env = fixture.engine()
        fixture.focus(env, 3)
        env.controller.cycle_focus(true)
        a.equal(env.dispatched[#env.dispatched].window, "address:window1")
        env.controller.cycle_focus(false)
        a.equal(env.dispatched[#env.dispatched].window, "address:window2")
        env.controller.swap_direction("l")
        a.equal(env.dispatched[#env.dispatched], "swapdirection l")
    end,

    ["swapwithmaster exchanges positions"] = function ()
        local env = fixture.engine()
        fixture.focus(env, 3)
        env.controller.definition.layout_msg(env.context, "swapwithmaster")
        a.equal(table.concat(env.ws.order, ","), "3,2,1")
    end,

    ["promote preserves other order and demote moves master to end"] = function ()
        local env = fixture.engine()
        fixture.focus(env, 3)
        env.controller.definition.layout_msg(env.context, "promote")
        a.equal(table.concat(env.ws.order, ","), "3,1,2")
        env.controller.definition.layout_msg(env.context, "demote")
        a.equal(table.concat(env.ws.order, ","), "1,2,3")
    end,

    ["next and previous swaps wrap"] = function ()
        local env = fixture.engine()
        fixture.focus(env, 3)
        env.controller.definition.layout_msg(env.context, "swapnext")
        a.equal(table.concat(env.ws.order, ","), "3,2,1")
        env.controller.definition.layout_msg(env.context, "swapprev")
        a.equal(table.concat(env.ws.order, ","), "1,2,3")
    end,

    ["close clears addresses and selects previous at end"] = function ()
        local env = fixture.engine()
        fixture.focus(env, 3)
        env.hooks["window.close"](env.windows[3])
        a.equal(env.ws.addresses["3"], nil)
        a.equal(env.ws.selected_id, "2")
        a.equal(a.read(env.status_path):find("window3", 1, true), nil)
    end,

    ["moving a window clears source ordering and status"] = function ()
        local env = fixture.engine()
        env.hooks["window.move_to_workspace"](env.windows[2], { id = 12 })
        a.equal(table.concat(env.ws.order, ","), "1,3")
        a.equal(env.ws.addresses["2"], nil)
        a.equal(a.read(env.status_path):find("window2", 1, true), nil)
    end,

    ["empty recalculation prunes floating moved and closed windows"] = function ()
        local env = fixture.engine()
        env.windows[1].floating = true
        env.windows[2].workspace = { id = 12 }
        env.windows[3].mapped = false
        env.controller.definition.recalculate(env.empty)
        a.equal(#env.ws.order, 0)
        a.equal(a.read(env.status_path), "10 FULLSCREEN 1\n")
        env.windows[1].floating = false
        env.context.targets = { env.context.targets[1] }
        env.controller.definition.recalculate(env.context)
        a.equal(table.concat(env.ws.order, ","), "1")
    end,

    ["workspace removal clears windows but retains preferences"] = function ()
        local env = fixture.engine()
        env.hooks["workspace.removed"]({ id = 10 })
        a.equal(#env.ws.order, 0)
        a.equal(env.ws.active_layout.name, "fullscreen")
    end,

    ["empty workspace preferences remain independent and persist"] = function ()
        local env = fixture.engine()
        env.focused_workspace = { id = 11 }
        env.controller.definition.layout_msg(env.empty, "reflect")
        a.equal(Store.layout_label(env.ws), "FULLSCREEN")
        a.equal(Store.layout_label(env.controller.store.workspaces["id:11"]), "TALL@0.500:R")
        local restored = Store.new(fixture.registry())
        Persistence.load(restored, env.state_path, a.unexpected)
        a.equal(Store.layout_label(restored.workspaces["id:11"]), "TALL@0.500:R")
        a.equal(Store.workspace(restored, env.empty), nil)
    end,

    ["reset restores workspace modifiers without changing strategy or order"] = function ()
        local env = fixture.engine()
        local other = assert(Store.workspace(env.controller.store, env.empty, { id = 11 }))
        other.reflect = true
        other.layout_state.tall.ratio = 0.65
        env.ws.active_layout = env.controller.store.registry.by_name.wide
        env.ws.order = { "3", "1", "2" }
        fixture.focus(env, 3)
        env.ws.layout_state.tall.ratio = 0.8
        env.ws.layout_state.wide.ratio = 0.7
        env.ws.layout_state.three_col.ratio = 0.6
        env.ws.reflect = true
        env.controller.definition.layout_msg(env.context, "reset")
        a.equal(env.ws.active_layout.name, "wide")
        a.equal(table.concat(env.ws.order, ","), "3,1,2")
        a.equal(env.ws.selected_id, "3")
        a.equal(env.ws.reflect, false)
        a.equal(env.ws.layout_state.tall.ratio, 0.5)
        a.equal(env.ws.layout_state.wide.ratio, 0.5)
        a.equal(env.ws.layout_state.three_col.ratio, 1 / 3)
        a.equal(other.reflect, true)
        a.equal(other.layout_state.tall.ratio, 0.65)
        local restored = Store.new(fixture.registry())
        Persistence.load(restored, env.state_path, a.unexpected)
        a.equal(Store.layout_label(restored.workspaces["id:10"]), "WIDE@0.500")
        a.equal(restored.workspaces["id:10"].layout_state.three_col.ratio, 1 / 3)
    end,

    ["reset also works on an empty fullscreen workspace"] = function ()
        local env = fixture.engine()
        env.ws.reflect = true
        env.ws.layout_state.tall.ratio = 0.8
        env.controller.definition.layout_msg(env.empty, "reset")
        a.equal(env.ws.active_layout.name, "fullscreen")
        a.equal(env.ws.reflect, false)
        a.equal(env.ws.layout_state.tall.ratio, 0.5)
    end,

    ["layout cycling wraps in both directions"] = function ()
        local env = fixture.engine()
        env.controller.definition.layout_msg(env.empty, "tall")
        env.controller.definition.layout_msg(env.empty, "prevlayout")
        a.equal(env.ws.active_layout.name, "fullscreen")
        env.controller.definition.layout_msg(env.empty, "nextlayout")
        a.equal(env.ws.active_layout.name, "tall")
    end,

    ["current strategy names select the matching layout"] = function ()
        local env = fixture.engine()
        for _, name in ipairs({ "tall", "wide", "three_col", "fullscreen" }) do
            a.equal(env.controller.definition.layout_msg(env.empty, name), true)
            a.equal(env.ws.active_layout.name, name)
        end
    end,

    ["empty layout messages return an error without crashing"] = function ()
        local env = fixture.engine()
        a.equal(type(env.controller.definition.layout_msg(env.context, "")), "string")
    end
}
