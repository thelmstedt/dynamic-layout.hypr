package.path = "lua/?.lua;./?.lua;" .. package.path

local passed, failed = 0, 0
assert(#arg > 0, "run tests/test.sh [tests/<suite>_test.lua ...]")

local function failure(name, message)
    failed = failed + 1
    io.stderr:write("FAIL " .. name .. "\n" .. tostring(message) .. "\n")
end

for _, path in ipairs(arg) do
    local loaded, suite = xpcall(function () return dofile(path) end, debug.traceback)
    if not loaded then
        failure(path, suite)
    else
        local names = {}
        for name in pairs(suite) do
            names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
            -- Restore mocked globals even when an assertion throws. Every test builds
            -- its own fixture; cases do not depend on earlier tests' mutations.
            local original_hl, execute, rename, getenv = rawget(_G, "hl"), os.execute, os.rename, os.getenv
            local ok, err = xpcall(suite[name], debug.traceback)
            rawset(_G, "hl", original_hl)
            os.execute, os.rename, os.getenv = execute, rename, getenv
            if ok then
                passed = passed + 1
                print("PASS " .. path .. " :: " .. name)
            else
                failure(path .. " :: " .. name, err)
            end
        end
    end
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
