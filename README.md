# dynamic-layout.hypr

A pure lua plugin for dynamic per-workspace layouts in hyprland, with behaviour lifted from xmonad.

## Features

- per workspace layouts
- tall, wide, fullscreen and three-column layouts
- focus, swap, reflect and grow/shrink for each layout
- layouts persist on hyprland reload and machine restart

## Configuration

```lua
-- or wherever you've cloned it
local root = os.getenv("HOME") .. "/projects/dynamic-layout.hypr" 
package.path = root .. "/lua/?.lua;" .. package.path

-- call setup once and keep around for keybinds
local layout = require("dynamic_layout").setup() 

-- use the newly registered layout
hl.config({ general = { layout = "lua:dynamic" } })

-- useful keybinds
hl.bind("SUPER + F1", hl.dsp.layout("fullscreen"))
hl.bind("SUPER + F2", hl.dsp.layout("tall"))
hl.bind("SUPER + F3", hl.dsp.layout("wide"))
hl.bind("SUPER + F4", hl.dsp.layout("three_col"))
hl.bind("SUPER + Space", layout.next_layout)
hl.bind("SUPER + Tab", layout.focus_next)
hl.bind("SUPER + Return", layout.swap_with_master)
hl.bind("SUPER + R", layout.reflect)
hl.bind("SUPER + F10", layout.reset)
hl.bind("SUPER + F11", layout.grow)
hl.bind("SUPER + F12", layout.shrink)
hl.bind("SUPER + SHIFT + left", function() layout.swap_direction("l") end)
hl.bind("SUPER + SHIFT + right", function() layout.swap_direction("r") end)
hl.bind("SUPER + SHIFT + up", function() layout.swap_direction("u") end)
hl.bind("SUPER + SHIFT + down", function() layout.swap_direction("d") end)

```

See [examples/hyprland.lua](examples/hyprland.lua) for a more complete setup

## Anti-features

We lose 
- click and drag window resize - `layout.grow` and `layout.shrink` provided as a poor substitute.
- click and drag repositioning - `layout.swap_direction` for keyboard substitute

Floating windows out of the layouts is a little painful, but resizing and moving works once they're floating. 

```lua
-- floating
hl.bind(mainMod .. " + T", hl.dsp.window.float({ action = "set" }))
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.float({ action = "set" }))
-- once floating, moving works fine
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
-- likewise resizing
hl.bind(mainMod .. " + SHIFT + mouse:273", hl.dsp.window.resize(), { mouse = true })
```


## State

State is tracked in files in `$XDG_STATE_HOME/dynamic-layout.hypr/`

We track state in two separate files:

- `settings` is restored on startup - all workspace layout settings
- `status` is overwritten on startup and never restored.

`settings` is restored on startup stores all strategy preferences. Window-close,
workspace-move, and workspace-removal hooks clear transient state while retaining
workspace preferences. Empty recalculations reconcile against live compositor
windows instead of assuming that the focused workspace is the one recalculating.

`status` is overwritten on startup and stores workspace, layout details and open
window addresses. This is intended for external consumers (e.g. quickshell)


## Tests

Run `just test` to checks Lua syntax, runs Lua Language Server diagnostics,
and runs the layout regression tests with a mocked Hyprland API.

Requires Lua 5.4 (`lua` and `luac`), `lua-language-server`, and Hyprland's Lua
stubs. The stub location defaults to `/usr/share/hypr/stubs` in `.luarc.json`;
adjust it if your installation uses another location.

