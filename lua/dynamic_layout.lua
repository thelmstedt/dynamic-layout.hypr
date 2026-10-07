local Engine = require("dynamic_layout.framework.engine")
local Registry = require("dynamic_layout.framework.registry")

---@class DynamicLayoutModule
local M = {}

---@return string
local function state_directory()
    local base = os.getenv("XDG_STATE_HOME")
    if not base or base:sub(1, 1) ~= "/" then
        local home = os.getenv("HOME")
        assert(home and home:sub(1, 1) == "/", "dynamic_layout requires HOME or an absolute XDG_STATE_HOME")
        base = home .. "/.local/state"
    end
    return base .. "/dynamic-layout.hypr"
end

---@param directory string
---@return string
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

--- The built-in strategies, composed the way a user would in their own config:
--- a configured master/stack and centered-stack, each paired with its mirror,
--- plus fullscreen. `wide` and `three_row` are not separate implementations.
---@return LayoutStrategy[]
local function default_strategies()
    local tall = require("dynamic_layout.strategies.tall")
    local three_col = require("dynamic_layout.strategies.three_col")
    local fullscreen = require("dynamic_layout.strategies.fullscreen")
    local mirror = require("dynamic_layout.strategies.mirror")

    local full = fullscreen("fullscreen")
    local tall = tall("tall", { nmaster = 1, ratio = 1 / 2 })
    local wide = mirror(tall, "wide")
    local cols = three_col("3cols", { ratio = 1 / 3 })
    local rows = mirror(cols, "3rows")
    return { full, tall, wide, cols, rows }
end

--- Register the layout and return helpers for user-defined keybindings.
--- Call once per configuration load, before selecting lua:dynamic.
---@param options? { strategies?: LayoutStrategy[], resize_delta?: number }
---@return LayoutController
function M.setup(options)
    options = options or {}
    local registry = Registry.new(options.strategies or default_strategies())

    local directory = ensure_directory(state_directory())

    return Engine.register({
        registry = registry,
        resize_delta = options.resize_delta,
        state_path = (directory .. "/state.json")
    })
end

return M
