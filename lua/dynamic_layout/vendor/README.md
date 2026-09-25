# Vendored dependencies

`json.lua` is an unmodified copy of [rxi/json.lua](https://github.com/rxi/json.lua),
version 0.1.2, pinned to commit `dbf4b2dd2eb7c23be2773c89eb059dadd6436f94`.
Its MIT license is included in `json.LICENSE` and in the source header.

```lua
local json = require("dynamic_layout.vendor.json")
local text = json.encode({ version = 1 })
local data = json.decode(text)
```

Both operations raise errors on failure; use `pcall` when loading state from disk.
Empty tables encode as arrays (`[]`); JSON null decodes to nil. Object key order
is unspecified, numbers encode with 14 significant digits, and output is compact.
Keep these limits in mind when implementing persistence and snapshot comparisons.

To update, copy `json.lua` and `LICENSE` from an explicit upstream commit,
update the pin above, and run `just test`.
