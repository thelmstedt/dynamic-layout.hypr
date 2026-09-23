local Engine = require("dynamic_layout.framework.engine")
local Registry = require("dynamic_layout.framework.registry")

local M = {}

local function state_directory()
    local base = os.getenv("XDG_STATE_HOME")
    if not base or base:sub(1, 1) ~= "/" then
        local home = os.getenv("HOME")
        assert(home and home:sub(1, 1) == "/", "dynamic_layout requires HOME or an absolute XDG_STATE_HOME")
        base = home .. "/.local/state"
    end
    return base .. "/dynamic-layout.hypr"
end

local function ensure_directory(directory)
    -- Quote the path for the shell, including embedded single quotes.
    local quoted = "'" .. directory:gsub("'", "'\\''") .. "'"
    local ok, reason, code = os.execute("umask 077; mkdir -p -- " .. quoted)
    if ok ~= true and ok ~= 0 then
        -- Hyprland can reap the child before Lua collects its exit status (ECHILD).
        -- Check the resulting directory instead of treating that as mkdir failure.
        local existing = io.open(directory .. "/.", "r")
        assert(
            existing,
            "could not create dynamic layout state directory: " .. directory
                .. " (" .. tostring(reason)
                .. ": " .. tostring(code)
                .. ")"
        )
        existing:close()
    end
    return directory
end

--- Register the layout and return helpers for user-defined keybindings.
--- Call once per configuration load, before selecting lua:dynamic.
---@return LayoutController
function M.setup()
    local registry = Registry.new({
        (require("dynamic_layout.strategies.tall")),
        (require("dynamic_layout.strategies.wide")),
        (require("dynamic_layout.strategies.three_col")),
        (require("dynamic_layout.strategies.fullscreen"))
    })

    local directory = ensure_directory(state_directory())

    return Engine.register({
        registry = registry,
        state_path = (directory .. "/settings"),
        status_path = (directory .. "/status")
    })
end

return M
