-- Add this to your existing hyprland.lua. Adjust root to your checkout.
-- Call setup once and keep its controller for the keybinding callbacks below.
local root = os.getenv("HOME") .. "/projects/dynamic-layout.hypr"
package.path = root .. "/lua/?.lua;" .. package.path

local layout = require("dynamic_layout").setup()

-- Ensure later configuration files also use lua:dynamic if they set the layout.
hl.config({ general = { layout = "lua:dynamic" } })

--- example keybinds

local mainMod = "SUPER"

-- Select, and cycle workspace layouts.
hl.bind(mainMod .. " + F1", hl.dsp.layout("fullscreen"))
hl.bind(mainMod .. " + F2", hl.dsp.layout("tall"))
hl.bind(mainMod .. " + F3", hl.dsp.layout("wide"))
hl.bind(mainMod .. " + F4", hl.dsp.layout("three_col"))
hl.bind(mainMod .. " + Space", layout.next_layout)
hl.bind(mainMod .. " + SHIFT + Space", layout.prev_layout)

-- reflect the current layout
hl.bind(mainMod .. " + R", layout.reflect)

-- Resize the focused side of the current layout.
hl.bind(mainMod .. " + F11", layout.grow)
hl.bind(mainMod .. " + F12", layout.shrink)

-- Reset this workspace's reflection and ratios, keeping its current strategy.
hl.bind(mainMod .. " + F10", layout.reset)

-- Exchange with master, or promote while preserving the other windows' order.
-- layout.demote sends the focused master to the end.
hl.bind(mainMod .. " + Return", layout.swap_with_master)
hl.bind("CTRL + Return", layout.swap_with_master)
hl.bind("CTRL + SHIFT + Return", layout.promote)

-- Cycle and swap focus
hl.bind(mainMod .. " + Tab", layout.focus_next)
hl.bind(mainMod .. " + bracketright", layout.focus_next)
hl.bind(mainMod .. " + SHIFT + bracketright", layout.swap_next)

hl.bind(mainMod .. " + SHIFT + Tab", layout.focus_prev)
hl.bind(mainMod .. " + bracketleft", layout.focus_prev)
hl.bind(mainMod .. " + SHIFT + bracketleft", layout.swap_prev)

-- move/swap windows by direction.
hl.bind(mainMod .. " + left", function() layout.move_direction("l") end)
hl.bind(mainMod .. " + right", function() layout.move_direction("r") end)
hl.bind(mainMod .. " + up", function() layout.move_direction("u") end)
hl.bind(mainMod .. " + down", function() layout.move_direction("d") end)

hl.bind(mainMod .. " + SHIFT + left", function() layout.swap_direction("l") end)
hl.bind(mainMod .. " + SHIFT + right", function() layout.swap_direction("r") end)
hl.bind(mainMod .. " + SHIFT + up", function() layout.swap_direction("u") end)
hl.bind(mainMod .. " + SHIFT + down", function() layout.swap_direction("d") end)



-- floating
hl.bind(mainMod .. " + T", function () hl.dispatch(hl.dsp.window.float({ action = "set" })) end)
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.float({ action = "set" }))
-- moving
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
-- resizing
hl.bind(mainMod .. " + SHIFT + mouse:273", hl.dsp.window.resize(), { mouse = true })
