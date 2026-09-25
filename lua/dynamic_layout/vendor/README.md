# Vendored dependencies

`json.lua` is based on [rxi/json.lua](https://github.com/rxi/json.lua),
version 0.1.2, pinned to commit `dbf4b2dd2eb7c23be2773c89eb059dadd6436f94`.
Its MIT license is included in `json.LICENSE` and in the source header.

```lua
local json = require("dynamic_layout.vendor.json")
local text = json.encode({ version = 1 })
local data = json.decode(text)
```

Both operations raise errors on failure; use `pcall` when loading state from disk.
Empty tables encode as arrays (`[]`); JSON null decodes to nil. Output is compact.
Two local encoder patches sort object entries for deterministic snapshots and
use 17 significant digits to preserve double precision across reloads.

To update, copy `json.lua` and `LICENSE` from an explicit upstream commit,
update the pin above, reapply the two marked local patches, and run `just test`.
