local a = require("tests.support.assertions")
local fixture = require("tests.support.fixtures")
local Store = require("dynamic_layout.framework.store")
local json = require("dynamic_layout.vendor.json")
local Persistence = require("dynamic_layout.framework.persistence")

return {
    ["custom strategy fields round trip unchanged"] = function ()
        local Registry = require("dynamic_layout.framework.registry")
        local fullscreen = require("dynamic_layout.strategies.fullscreen")("fullscreen")
        local registry = Registry.new({ {
            name = "custom",
            new_state = function() return { options = { count = 2, enabled = true } } end,
            geometry = fullscreen.geometry,
            neighbor = fullscreen.neighbor
        } })
        local store = Store.new(registry)
        local path = fixture.path("custom")
        a.write(path, json.encode({ version = 1, workspaces = { ["id:7"] = {
            active_layout = "custom", reflect = false, order = {},
            layout_state = { custom = { options = { count = 4 }, extra = { "a", "b" } } }
        } } }))
        Persistence.load(store, path, a.unexpected)
        local state = json.decode(Persistence.snapshot(store)).workspaces["id:7"].layout_state.custom
        a.equal(state.options.count, 4)
        a.equal(state.options.enabled, nil)
        a.equal(state.extra[2], "b")
    end,

    ["decode errors include the parser diagnostic"] = function ()
        local path = fixture.path("syntax")
        local content = '{"version":1,\n"workspaces": [}'
        a.write(path, content)
        local ok, diagnostic = pcall(json.decode, content)
        a.equal(ok, false)
        local errors = {}
        Persistence.load(Store.new(fixture.registry()), path, function(message) errors[#errors + 1] = message end)
        a.equal(#errors, 1)
        a.equal(errors[1], "read " .. path .. ": " .. diagnostic)
    end,

    ["invalid documents report errors without replacing settings"] = function ()
        local store, ws = fixture.store()
        local path = fixture.path("invalid")
        for _, content in ipairs({ "{broken", "null", "42", '{"version":2,"workspaces":[]}', "id:7 TALL@0.6" }) do
            a.write(path, content)
            local errors = {}
            Persistence.load(store, path, function(message) errors[#errors + 1] = message end)
            a.equal(#errors, 1)
            a.equal(store.workspaces["id:7"], ws)
        end
    end,

    ["malformed workspace abandons the entire snapshot"] = function ()
        local store, original = fixture.store()
        local data = json.decode(Persistence.snapshot(store))
        data.workspaces["id:8"] = false
        local path = fixture.path("invalid-workspace")
        a.write(path, json.encode(data))
        local errors = {}
        Persistence.load(store, path, function(message) errors[#errors + 1] = message end)
        a.equal(#errors, 1)
        a.equal(store.workspaces["id:7"], original)
        a.equal(store.workspaces["id:8"], nil)
    end,

    ["JSON preserves escaped identifiers and strategy state"] = function ()
        local store, ws = fixture.store()
        local key = 'name:space "quote"\\slash\n'
        store.workspaces["id:7"] = nil
        store.workspaces[key] = ws
        ws.order = { 'id,"\\\n', "second" }
        ws.layout_state.three_col.focus_row = 5
        local path = fixture.path("escaped")
        a.write(path, Persistence.snapshot(store))
        local restored = Store.new(fixture.registry())
        Persistence.load(restored, path, a.unexpected)
        a.equal(restored.workspaces[key].order[1], ws.order[1])
        a.equal(restored.workspaces[key].layout_state.three_col.ratio, 1 / 3)
        local state = restored.workspaces[key].layout_state.three_col --[[@as CenteredStackState]]
        a.equal(state.focus_row, 5)
        a.equal(json.decode(Persistence.snapshot(store)).workspaces[key].active_layout, ws.active_layout)
    end,

    ["window order restores without session metadata"] = function ()
        local store, ws = fixture.store()
        ws.order = { "b", "a", "id,with delimiter" }
        local path = fixture.path("settings")
        for _, prefix in ipairs({ "", " \n" }) do
            a.write(path, prefix .. Persistence.snapshot(store))
            local restored = Store.new(fixture.registry())
            Persistence.load(restored, path, a.unexpected)
            local restored_ws = restored.workspaces["id:7"]
            a.equal(table.concat(restored_ws.order, "|"), "b|a|id,with delimiter")
            a.equal(restored_ws.layout_state.tall.ratio, 0.61)
            a.equal(next(restored_ws.addresses), nil)
        end
    end,

    ["layout names restore strategies with and without ratios"] = function ()
        local registry = fixture.registry()
        local path = fixture.path("labels")
        for _, strategy in ipairs(registry.layouts) do
            local store = Store.new(registry)
            local ws = assert(Store.workspace(store, { targets = {} }, { id = 7 }))
            ws.active_layout = strategy.name
            ws.reflect = true
            local state = ws.layout_state[strategy.name]
            if state.ratio then state.ratio = 0.637 end
            a.write(path, Persistence.snapshot(store))
            local restored = Store.new(registry)
            Persistence.load(restored, path, a.unexpected)
            local loaded = restored.workspaces["id:7"]
            a.equal(loaded.active_layout, strategy.name)
            a.equal(loaded.reflect, true)
            a.equal(loaded.layout_state[strategy.name].ratio, state.ratio)

        end
    end,

    ["settings retain ratios and order but discard window addresses"] = function ()
        local store = fixture.store()
        local path = fixture.path("settings")
        a.equal(Persistence.write(Persistence.writer(path, a.unexpected), Persistence.snapshot(store)), true)
        local restored = Store.new(fixture.registry())
        Persistence.load(restored, path, a.unexpected)
        local ws = restored.workspaces["id:7"]
        a.equal(ws.active_layout, "fullscreen")
        a.equal(ws.reflect, true)
        a.equal(ws.layout_state.tall.ratio, 0.61)
        a.equal(ws.layout_state.wide.ratio, 0.72)
        a.equal(ws.layout_state.three_col.ratio, 1 / 3)
        a.equal(next(ws.addresses), nil)
        a.equal(ws.selected_id, nil)
        a.equal(table.concat(ws.order, ","), "a,b")
    end,

    ["saving another workspace preserves unvisited settings"] = function ()
        local store = fixture.store()
        local path = fixture.path("settings")
        local writer = Persistence.writer(path, a.unexpected)
        Persistence.write(writer, Persistence.snapshot(store))
        local restored = Store.new(fixture.registry())
        Persistence.load(restored, path, a.unexpected)
        Store.workspace(restored, { targets = {} }, { id = 8 })
        Persistence.write(writer, Persistence.snapshot(restored))
        local again = Store.new(fixture.registry())
        Persistence.load(again, path, a.unexpected)
        a.equal(again.workspaces["id:7"].layout_state.wide.ratio, 0.72)
    end,

    ["snapshot exposes workspace data and layout metadata"] = function ()
        local store, ws = fixture.store()
        local snapshot = json.decode(Persistence.snapshot(store))
        local saved = snapshot.workspaces["id:7"]
        a.equal(saved.active_layout, "fullscreen")
        a.equal(saved.selected_id, "b")
        a.equal(saved.addresses[saved.order[1]], "abc")
        a.equal(saved.addresses[saved.order[2]], "def")
        a.equal(saved.layout_state.tall.ratio, ws.layout_state.tall.ratio)
        a.equal(snapshot.layouts.fullscreen.single_window, true)
        a.equal(snapshot.layouts.tall.single_window, false)
    end,

    ["single-window status follows the capability rather than the name"] = function ()
        local Registry = require("dynamic_layout.framework.registry")
        local fullscreen = require("dynamic_layout.strategies.fullscreen")("fullscreen")
        local custom = {
            name = "custom",
            single_window = true,
            new_state = fullscreen.new_state,
            geometry = fullscreen.geometry,
            neighbor = fullscreen.neighbor
        }
        local store = Store.new(Registry.new({ custom }))
        local ws = assert(Store.for_workspace(store, { id = 7 }))
        a.equal(json.decode(Persistence.snapshot(store)).layouts[custom.name].single_window, true)
        custom.single_window = false
        a.equal(json.decode(Persistence.snapshot(store)).layouts[custom.name].single_window, false)
        custom.single_window = nil
        a.equal(json.decode(Persistence.snapshot(store)).layouts[custom.name].single_window, false)
        custom.name = "fullscreen"
        ws.layout_state.fullscreen = {}
        a.equal(json.decode(Persistence.snapshot(store)).layouts[custom.name].single_window, false)
    end,

    ["unchanged snapshots do not rewrite files"] = function ()
        local store = fixture.store()
        local writer = Persistence.writer(fixture.path("settings"), a.unexpected)
        local snapshot = Persistence.snapshot(store)
        Persistence.write(writer, snapshot)
        local rename, calls = os.rename, 0
        ---@diagnostic disable-next-line: duplicate-set-field
        os.rename = function (from, to)
            calls = calls + 1
            return rename(from, to)
        end
        Persistence.write(writer, Persistence.snapshot(store))
        Persistence.write(writer, Persistence.snapshot(store))
        a.equal(calls, 0)
    end,

    ["write failures report once and can recover"] = function ()
        local errors = {}
        local writer = Persistence.writer(fixture.path("missing") .. "/settings", function (message)
            errors[#errors + 1] = message
        end)
        a.equal(Persistence.write(writer, "snapshot"), false)
        a.equal(Persistence.write(writer, "snapshot"), false)
        a.equal(#errors, 1)
        a.equal(writer.content, nil)
        writer.path = fixture.path("retry")
        a.equal(Persistence.write(writer, "snapshot"), true)
        a.equal(a.read(writer.path), "snapshot")
    end,

    ["failed rename preserves the previous file"] = function ()
        local path, errors = fixture.path("settings"), {}
        a.write(path, "previous")
        local writer = Persistence.writer(
            path,
            function (message)
                errors[#errors + 1] = message
            end
        )
        ---@diagnostic disable-next-line: duplicate-set-field
        os.rename = function ()
            return nil, "simulated rename failure", 5
        end
        a.equal(Persistence.write(writer, "replacement"), false)
        a.equal(a.read(path), "previous")
        a.equal(#errors, 1)
    end
}
