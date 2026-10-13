# Type-check, then run the tests (what the old test.sh did in one pass).
test: check
	./luarocks test

# Static type checking with lua-language-server: validates the ---@class / @param
# annotations, undefined/missing fields, bad casts, etc. Requires
# lua-language-server on PATH (it is not a luarocks dependency).
check:
	lua-language-server --check="$(pwd)" --configpath="$(pwd)/.luarc.json" --logpath="$(mktemp -d)" --checklevel=Warning

# Bootstrap a fresh checkout: create the project-local luarocks tree and
# ./luarocks wrapper (scoped to lua_modules, keeping the committed rockspec and
# .gitignore), then install the test dependencies (busted) into it.
init:
	luarocks init --tree lua_modules --no-gitignore
	./luarocks test --prepare
