-- Restores globals that individual cases monkeypatch (the Hyprland API and os
-- hooks) so cases stay independent, matching the isolation the old runner gave.
-- Busted injects its hooks into each spec's environment rather than the shared
-- globals a required module sees, so the caller passes them in:
--   require("tests.support.sandbox")(before_each, after_each)
return function(before_each, after_each)
    local saved
    before_each(function()
        saved = {
            hl = rawget(_G, "hl"),
            getenv = os.getenv,
            execute = os.execute,
            rename = os.rename,
        }
    end)
    after_each(function()
        rawset(_G, "hl", saved.hl)
        os.getenv, os.execute, os.rename = saved.getenv, saved.execute, saved.rename
    end)
end
