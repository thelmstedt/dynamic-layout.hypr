local a = require("tests.support.assertions")
local fixture = require("tests.support.fixtures")
local Store = require("dynamic_layout.framework.store")
local Persistence = require("dynamic_layout.framework.persistence")

return {
    ["window order restores without session metadata"] = function ()
        local store, ws = fixture.store()
        ws.order = { "b", "a", "id,with delimiter" }
        local path = fixture.path("settings")
        for _, prefix in ipairs({ "", "# session=old-instance\n" }) do
            a.write(path, prefix .. Persistence.settings(store))
            local restored = Store.new(fixture.registry())
            Persistence.load(restored, path, a.unexpected)
            local restored_ws = restored.workspaces["id:7"]
            a.equal(table.concat(restored_ws.order, "|"), "b|a|id,with delimiter")
            a.equal(restored_ws.layout_state.tall.ratio, 0.61)
            a.equal(next(restored_ws.addresses), nil)
        end
    end,

    ["framework labels restore strategies with and without ratios"] = function ()
        local registry = fixture.registry()
        local path = fixture.path("labels")
        for _, strategy in ipairs(registry.layouts) do
            local store = Store.new(registry)
            local ws = assert(Store.workspace(store, { targets = {} }, { id = 7 }))
            ws.active_layout = strategy
            ws.reflect = true
            local state = ws.layout_state[strategy.name]
            if state.ratio then state.ratio = 0.637 end
            local label = strategy.name:upper() .. (state.ratio and "@0.637" or "") .. ":R"
            a.equal(Store.layout_label(ws), label)
            a.write(path, Persistence.settings(store))
            local restored = Store.new(registry)
            Persistence.load(restored, path, a.unexpected)
            a.equal(Store.layout_label(restored.workspaces["id:7"]), label)
            -- A bare name also selects a strategy without requiring a ratio.
            a.write(path, "id:7 " .. strategy.name:upper() .. "\n")
            Persistence.load(restored, path, a.unexpected)
            a.equal(restored.workspaces["id:7"].active_layout, strategy)
        end
    end,

    ["settings retain ratios and order but discard window addresses"] = function ()
        local store = fixture.store()
        local path = fixture.path("settings")
        a.equal(Persistence.write(Persistence.writer(path, a.unexpected), Persistence.settings(store)), true)
        local restored = Store.new(fixture.registry())
        Persistence.load(restored, path, a.unexpected)
        local ws = restored.workspaces["id:7"]
        a.equal(Store.layout_label(ws), "FULLSCREEN:R")
        a.equal(ws.layout_state.tall.ratio, 0.61)
        a.equal(ws.layout_state.wide.ratio, 0.72)
        a.equal(ws.layout_state.three_col.ratio, 1 / 3)
        a.equal(next(ws.addresses), nil)
        a.equal(table.concat(ws.order, ","), "a,b")
    end,

    ["saving another workspace preserves unvisited settings"] = function ()
        local store = fixture.store()
        local path = fixture.path("settings")
        local writer = Persistence.writer(path, a.unexpected)
        Persistence.write(writer, Persistence.settings(store))
        local restored = Store.new(fixture.registry())
        Persistence.load(restored, path, a.unexpected)
        Store.workspace(restored, { targets = {} }, { id = 8 })
        Persistence.write(writer, Persistence.settings(restored))
        local again = Store.new(fixture.registry())
        Persistence.load(again, path, a.unexpected)
        a.equal(again.workspaces["id:7"].layout_state.wide.ratio, 0.72)
    end,

    ["status reports current labels and ordered addresses"] = function ()
        local store, ws = fixture.store()
        a.equal(Persistence.status(store), "7 FULLSCREEN:R 1 abc def\n")
        ws.active_layout = store.registry.by_name.tall
        a.equal(Persistence.status(store), "7 TALL@0.610:R 0 abc def\n")
    end,

    ["unchanged snapshots do not rewrite files"] = function ()
        local store = fixture.store()
        local writer = Persistence.writer(fixture.path("settings"), a.unexpected)
        local snapshot = Persistence.settings(store)
        Persistence.write(writer, snapshot)
        local rename, calls = os.rename, 0
        ---@diagnostic disable-next-line: duplicate-set-field
        os.rename = function (from, to)
            calls = calls + 1
            return rename(from, to)
        end
        Persistence.write(writer, snapshot)
        Persistence.write(writer, snapshot)
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
