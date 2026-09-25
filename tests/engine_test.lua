local a = require("tests.support.assertions")
local fixture = require("tests.support.fixtures")
local Store = require("dynamic_layout.framework.store")
local Persistence = require("dynamic_layout.framework.persistence")

return {
    ["window reordering survives repeated config reloads with partial target lists"] = function ()
        local env = fixture.engine()
        fixture.focus(env, 3)
        env.controller.swap_with_master()
        a.equal(table.concat(env.ws.order, ","), "3,2,1")
        for _ = 1, 2 do
            require("dynamic_layout.framework.engine").register({
                registry = fixture.registry(), state_path = env.state_path, status_path = env.status_path
            })
            -- Startup publishing and an empty pass must not discard saved order.
            env.registered.dynamic.recalculate(env.empty)
            -- Hyprland rebuilds the layout one target at a time on reload.
            local partial = { area = env.context.area, targets = {} }
            for _, target in ipairs(env.context.targets) do
                partial.targets[#partial.targets + 1] = target
                env.registered.dynamic.recalculate(partial)
            end
            local restored = Store.new(fixture.registry())
            Persistence.load(restored, env.state_path, a.unexpected)
            a.equal(table.concat(restored.workspaces["id:10"].order, ","), "3,2,1")
        end
    end,

    ["reload removes closed floating and moved windows from saved order"] = function ()
        local env = fixture.engine(4)
        fixture.focus(env, 4)
        env.controller.promote()
        env.windows[1].workspace = { id = 11 }
        env.windows[2].floating = true
        env.windows[3].mapped = false
        require("dynamic_layout.framework.engine").register({
            registry = fixture.registry(), state_path = env.state_path, status_path = env.status_path
        })
        local restored = Store.new(fixture.registry())
        Persistence.load(restored, env.state_path, a.unexpected)
        a.equal(table.concat(restored.workspaces["id:10"].order, ","), "4")
    end,

    ["external messages select layouts but do not execute controller operations"] = function ()
        local env = fixture.engine()
        env.registered.dynamic.layout_msg(env.context, "tall")
        for _, message in ipairs({ "shrink", "ratio 0.7", "reflect", "reset", "swapnext", "focusactive" }) do
            a.equal(type(env.registered.dynamic.layout_msg(env.context, message)), "string")
        end
        a.near(env.ws.layout_state.tall.ratio, 0.5)
        a.equal(env.ws.reflect, false)
        a.equal(table.concat(env.ws.order, ","), "1,2,3")
        a.equal(env.registered.dynamic.layout_msg(env.empty, "_refresh"), true)
        a.equal(table.concat(env.ws.order, ","), "1,2,3")
        a.equal(type(env.registered.dynamic.layout_msg(env.context, "full")), "string")
        a.equal(env.registered.dynamic.layout_msg(env.context, "fullscreen"), true)
        a.equal(env.ws.active_layout.name, "fullscreen")
    end,

    ["fullscreen retains selection when workspace loses focus"] = function ()
        local env = fixture.engine()
        a.equal(Store.layout_label(env.ws), "FULLSCREEN")
        a.box(env.boxes[2], { x = 0, y = 0, w = 100, h = 100 })
        assert(env.boxes[1].x < 0 and env.boxes[3].x < 0)
        fixture.focus(env, nil)
        env.boxes = {}
        env.registered.dynamic.recalculate(env.context)
        a.box(env.boxes[2], { x = 0, y = 0, w = 100, h = 100 })
    end,

    ["focus hooks select fullscreen windows and ignore floating focus"] = function ()
        local env = fixture.engine()
        fixture.focus(env, 3)
        a.equal(env.ws.selected_id, "3")
        a.dispatch(env.dispatched[#env.dispatched], "layout", "_refresh")
        env.registered.dynamic.recalculate(env.context)
        a.box(env.boxes[3], { x = 0, y = 0, w = 100, h = 100 })
        local before = #env.dispatched
        env.windows[1].floating = true
        fixture.focus(env, 1)
        a.equal(env.ws.selected_id, "3")
        a.equal(#env.dispatched, before)
    end,

    ["focus cycles in order with wrapping and falls back without an active window"] = function ()
        local env = fixture.engine()
        fixture.focus(env, 3)
        env.controller.cycle_focus(true)
        a.dispatch(env.dispatched[#env.dispatched], "focus", { window = "address:window1" })
        env.controller.cycle_focus(false)
        a.dispatch(env.dispatched[#env.dispatched], "focus", { window = "address:window2" })
        fixture.focus(env, nil)
        for _, next in ipairs({ true, false }) do
            env.controller.cycle_focus(next)
            a.dispatch(env.dispatched[#env.dispatched], "window.cycle_next", { next = next })
        end
    end,

    ["promote preserves other order and demote moves master to end"] = function ()
        local env = fixture.engine()
        fixture.focus(env, 3)
        env.controller.promote()
        a.equal(table.concat(env.ws.order, ","), "3,1,2")
        env.controller.demote()
        a.equal(table.concat(env.ws.order, ","), "1,2,3")
    end,

    ["next and previous swaps wrap"] = function ()
        local env = fixture.engine()
        fixture.focus(env, 3)
        env.controller.swap_next()
        a.equal(table.concat(env.ws.order, ","), "3,2,1")
        env.controller.swap_prev()
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
        env.registered.dynamic.recalculate(env.empty)
        a.equal(#env.ws.order, 0)
        a.equal(a.read(env.status_path), "10 FULLSCREEN 1\n")
        env.windows[1].floating = false
        env.context.targets = { env.context.targets[1] }
        env.registered.dynamic.recalculate(env.context)
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
        env.controller.reflect()
        a.equal(Store.layout_label(env.ws), "FULLSCREEN")
        a.equal(Store.layout_label(env.store.workspaces["id:11"]), "TALL@0.500:R")
        local restored = Store.new(fixture.registry())
        Persistence.load(restored, env.state_path, a.unexpected)
        a.equal(Store.layout_label(restored.workspaces["id:11"]), "TALL@0.500:R")
        a.equal(Store.workspace(restored, env.empty), nil)
    end,

    ["reset restores workspace modifiers without changing strategy or order"] = function ()
        local env = fixture.engine()
        local other = assert(Store.workspace(env.store, env.empty, { id = 11 }))
        other.reflect = true
        other.layout_state.tall.ratio = 0.65
        env.ws.active_layout = env.store.registry.by_name.wide
        env.ws.order = { "3", "1", "2" }
        fixture.focus(env, 3)
        env.ws.layout_state.tall.ratio = 0.8
        env.ws.layout_state.wide.ratio = 0.7
        env.ws.layout_state.three_col.ratio = 0.6
        env.ws.reflect = true
        env.controller.reset()
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

    ["current strategy names select the matching layout"] = function ()
        local env = fixture.engine()
        for _, name in ipairs({ "tall", "wide", "three_col", "fullscreen" }) do
            a.equal(env.registered.dynamic.layout_msg(env.empty, name), true)
            a.equal(env.ws.active_layout.name, name)
        end
    end,

    ["empty layout messages return an error without crashing"] = function ()
        local env = fixture.engine()
        a.equal(type(env.registered.dynamic.layout_msg(env.context, "")), "string")
    end
}
