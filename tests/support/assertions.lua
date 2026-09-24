local M = {}

function M.equal(actual, expected)
    assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

function M.near(actual, expected)
    assert(
        math.abs(actual - expected) < 0.000001,
        string.format("expected approximately %s, got %s", tostring(expected), tostring(actual))
    )
end

function M.box(actual, expected)
    for _, field in ipairs({ "x", "y", "w", "h" }) do
        M.near(actual[field], expected[field])
    end
end

function M.dispatch(actual, kind, options)
    M.equal(actual.kind, kind)
    if type(options) == "table" then
        for key, value in pairs(options) do M.equal(actual.options[key], value) end
        for key, value in pairs(actual.options) do M.equal(value, options[key]) end
    else
        M.equal(actual.options, options)
    end
end

function M.read(path)
    local file = assert(io.open(path))
    local content = file:read("*a")
    file:close()
    return content
end

function M.write(path, content)
    local file = assert(io.open(path, "w"))
    assert(file:write(content))
    assert(file:close())
end

function M.unexpected(message)
    error(message)
end

return M
