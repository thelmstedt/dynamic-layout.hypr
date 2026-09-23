local Store = require("dynamic_layout.framework.store")

local M = {}

local function encode(value)
    return (value:gsub("[^%w_%.:@%-]", function (c) return string.format("%%%02X", c:byte()) end))
end

local function decode(value)
    return (value:gsub("%%(%x%x)", function (hex) return string.char(tonumber(hex, 16)) end))
end

local function keys(workspaces)
    local result = {}
    for key in pairs(workspaces) do
        result[#result + 1] = key
    end
    table.sort(result)
    return result
end

local function restore_label(registry, ws, label)
    local base = label:match("^(.-):R$")
    ws.reflect = base ~= nil
    label = base or label
    for _, strategy in ipairs(registry.layouts) do
        if strategy.restore_label(ws.layout_state[strategy.name], label) then
            ws.active_layout = strategy
            return
        end
    end
end

function M.load(store, path, report)
    local file, err, code = io.open(path, "r")
    if not file then
        if code ~= 2 then report("read " .. path .. ": " .. tostring(err)) end
        return
    end
    for line in file:lines() do
        local fields = {}
        for field in line:gmatch("%S+") do
            fields[#fields + 1] = field
        end
        if fields[1] and fields[2] and fields[1]:sub(1, 1) ~= "#" then
            local key = decode(fields[1])
            local ws = Store.new_workspace(store.registry)
            restore_label(store.registry, ws, decode(fields[2]))
            for i = 3, #fields do
                local name, label = fields[i]:match("^([%w_]+)=(.+)$")
                local strategy = name and store.registry.by_name[name]
                if strategy then strategy.restore_label(ws.layout_state[name], decode(label)) end
                local ratio_name, value = fields[i]:match("^([%w_]+)%.ratio=(.+)$")
                local state = ratio_name and ws.layout_state[ratio_name]
                local ratio = tonumber(value)
                if state and state.ratio and ratio and ratio >= 0.1 and ratio <= 0.9 then
                    state.ratio = ratio
                end
            end
            store.workspaces[key] = ws
        end
    end
    file:close()
end

function M.settings(store)
    local lines = { "# dynamic-layout settings v1" }
    for _, key in ipairs(keys(store.workspaces)) do
        local ws = store.workspaces[key]
        local fields = { encode(key), encode(Store.layout_label(ws)) }
        for _, strategy in ipairs(store.registry.layouts) do
            local state = ws.layout_state[strategy.name]
            fields[#fields + 1] = strategy.name .. "=" .. encode(strategy.label(state))
            -- Status labels are rounded for display; settings must retain exact ratios.
            if state.ratio then
                fields[#fields + 1] = strategy.name .. ".ratio=" .. string.format("%.17g", state.ratio)
            end
        end
        lines[#lines + 1] = table.concat(fields, " ")
    end
    return table.concat(lines, "\n") .. "\n"
end

function M.status(store)
    local lines = {}
    for _, key in ipairs(keys(store.workspaces)) do
        local id = key:match("^id:(.+)$")
        if id then
            local ws = store.workspaces[key]
            -- Single-window mode is layout information, not a request to draw tabs.
            local fields = { id, Store.layout_label(ws), ws.active_layout.name == "fullscreen" and "1" or "0" }
            for _, window_id in ipairs(ws.order) do
                if ws.addresses[window_id] then fields[#fields + 1] = ws.addresses[window_id] end
            end
            lines[#lines + 1] = table.concat(fields, " ")
        end
    end
    return #lines > 0 and (table.concat(lines, "\n") .. "\n") or ""
end

-- A writer owns only IO state. Failed writes are reported and retried on the
-- next change; unchanged successful snapshots do not touch the filesystem.
function M.writer(path, report)
    return { path = path, report = report, content = nil, error = nil }
end

function M.write(writer, content)
    if writer.content == content then return true end
    local temporary = writer.path .. ".tmp"
    local file, err = io.open(temporary, "w")
    local ok
    if file then
        ok, err = file:write(content)
        local closed, close_error = file:close()
        if ok and not closed then
            ok, err = nil, close_error
        end
        if ok then ok, err = os.rename(temporary, writer.path) end
    end
    if not ok then
        if file then os.remove(temporary) end
        local message = "write " .. writer.path .. ": " .. tostring(err)
        if writer.error ~= message then writer.report(message) end
        writer.error = message
        return false
    end
    writer.content, writer.error = content, nil
    return true
end

return M
