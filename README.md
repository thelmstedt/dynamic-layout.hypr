# dynamic-layout.hypr

A pure lua plugin for dynamic per-workspace layouts in hyprland, with behaviour lifted from xmonad.

## Features

- dynamic, per-workspace layouts
- tall, wide, fullscreen, three-column and three-row layouts
- directional and ordered navigation for each layout
- switch focus, swap windows, reflect and grow/shrink for each layout
- workspace/layout persistence

## Anti-features

We lose

- click and drag window resize - `layout.grow` and `layout.shrink` provided as a poor substitute.
- click and drag repositioning - `layout.swap_direction` for keyboard substitute

Floating windows out of the layouts is a little painful, but resizing and moving works once they're floating.

## Configuration

Basic config

```lua
-- or wherever you've cloned it
local root = os.getenv("HOME") .. "/projects/dynamic-layout.hypr" 
package.path = root .. "/lua/?.lua;" .. package.path

-- by default setup registers: fullscreen, tall, wide, 3col, 3row layouts
local layout = require("dynamic_layout").setup() 

-- use the newly registered layout
hl.config({ general = { layout = "lua:dynamic" } })
```

Keybinds

```lua
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
hl.bind("SUPER + left", function() layout.focus_direction("l") end)
hl.bind("SUPER + right", function() layout.focus_direction("r") end)
hl.bind("SUPER + up", function() layout.focus_direction("u") end)
hl.bind("SUPER + down", function() layout.focus_direction("d") end)
hl.bind("SUPER + SHIFT + left", function() layout.swap_direction("l") end)
hl.bind("SUPER + SHIFT + right", function() layout.swap_direction("r") end)
hl.bind("SUPER + SHIFT + up", function() layout.swap_direction("u") end)
hl.bind("SUPER + SHIFT + down", function() layout.swap_direction("d") end)

-- floating
hl.bind("SUPER + T", hl.dsp.window.float({ action = "set" }))
hl.bind("SUPER + mouse:273", hl.dsp.window.float({ action = "set" }))
-- once floating, moving works fine
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
-- likewise resizing
hl.bind("SUPER + SHIFT + mouse:273", hl.dsp.window.resize(), { mouse = true })
```

Explicit strategy config:

```lua
-- this is the equivalent of require("dynamic_layout").setup()
local tall = require("dynamic_layout.strategies.tall")
local three_col = require("dynamic_layout.strategies.three_col")
local fullscreen = require("dynamic_layout.strategies.fullscreen")
local mirror = require("dynamic_layout.strategies.mirror")

                                                            -- xmonad equivalent
local full = fullscreen("fullscreen")                       -- Full
local tall = tall("tall", { nmaster = 1, ratio = 1 / 2 })   -- Tall 1 (3/100) (1/2)
local wide = mirror(tall, "wide")                           -- Mirror tall
local cols = three_col("3col", { ratio = 1 / 3 })           -- ThreeCol 1 (3/100) (1/3)
local rows = mirror(cols, "3rows")                          -- Mirror cols

local layout = require("dynamic_layout").setup({
    resize_delta = 3 / 100,                                 -- delta, shared by every layout
    strategies = { full, tall, wide, cols, rows },          -- order is important, determines cycle order
})
```

## Layout strategies

Our built-in strategies:

- `fullscreen` - simple fullscreen mode. hidden windows are rendered offscreen and switched in
- `tall` - master window next to subordinates
- `three_col` - master window with subordinates on both sides
- `mirror` takes a layout and constructs a new layout with the main axis swapped (i.e. u/d <-> l/r)

The engine provides 2 layout modifiers, applied on a per-workspace basis

- `reflect` swaps the windows around the main axis (e.g. M|s -> s|M, or s1|M|s2 -> s2|M|s1)
- `grow`/`shrink` adjusts the size of the master window

### Custom strategies

Documented in `LayoutStrategy` class. Main bits:

- `new_state()` returns a fresh JSON-serializable table for each workspace, persistence and reset
- `geometry(state, context, workspace)` returns a map of window ID to box in canonical (unreflected) orientation

```lua
local util = require("dynamic_layout.framework.util")

-- Equal-height rows. Returning geometry is the whole strategy: the framework
-- mirrors it for reflection (reversing the rows) and derives up/down navigation.
---@type LayoutStrategy<table>
local my_rows = {
    name = "my_rows", -- name to invoke the layout with hl.dsp.layout("my_rows")
    reflect_axis = "y", -- reflect swaps content around this axis
    new_state = function() return {} end, -- no state needed in our local methods

    -- geometry builds boxes for the framework to render/reflect/navigate/etc
    geometry = function(state, context, workspace)
        return util.stack_boxes(context, workspace.order, context.area, "vertical")
    end,
}

-- use it when you setup dynamic_layout alongside other strategies
local layout = require("dynamic_layout").setup({
    strategies = { full, tall, wide, cols, rows, my_rows },
})

```

## Tests

Run `just test` check syntax, types via lsp and layout unit tests. Tests against a mocked out hyprland api

Requires Lua 5.4 (`lua` and `luac`), `lua-language-server`, and Hyprland's Lua stubs configured in `./.luarc.json`

## State

State is published as JSON in `$XDG_STATE_HOME/dynamic-layout.hypr/state.json`
(or `$HOME/.local/state/dynamic-layout.hypr/state.json` when unset).
