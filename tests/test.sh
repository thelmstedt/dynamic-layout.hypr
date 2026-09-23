#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for tool in lua luac lua-language-server; do
    if ! command -v "$tool" >/dev/null; then
        echo "$tool is required" >&2
        exit 1
    fi
done

while IFS= read -r -d '' file; do
    luac -p "$file"
done < <(find lua examples tests -name '*.lua' -type f -print0)

test_dir="$(mktemp -d /tmp/dynamic-layout-tests.XXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT

lua-language-server --check="$repo_root" --configpath="$repo_root/.luarc.json" \
    --logpath="$test_dir/lua-language-server" --checklevel=Warning

if (( $# > 0 )); then
    suites=("$@")
else
    suites=(tests/*_test.lua)
fi
XDG_STATE_HOME="$test_dir" lua tests/run.lua "${suites[@]}"

echo "all tests: ok"
