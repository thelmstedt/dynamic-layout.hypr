local json = require("dynamic_layout.vendor.json")

---@alias PersistenceReporter fun(message: string)

---@class PersistenceWriter
---@field path string
---@field report PersistenceReporter
---@field content? string Last successfully written snapshot.
---@field error? string Last reported error, cleared after a successful write.

---@class LayoutPersistenceModule
local M = {}

---@param store LayoutStore
---@param path string
---@param report PersistenceReporter
function M.load(store, path, report)
    local file, err, code = io.open(path, "r")
    if not file then
        if code ~= 2 then report("read " .. path .. ": " .. tostring(err)) end
        return
    end
    local content, read_error = file:read("a")
    file:close()
    if not content then
        report("read " .. path .. ": " .. tostring(read_error))
        return
    end
    local ok, workspaces = pcall(function()
        local data = json.decode(content)
        assert(data.version == 1, "unsupported state version")
        for _, ws in pairs(data.workspaces) do
            ws.addresses, ws.selected_id = {}, nil
        end
        return data.workspaces
    end)
    if not ok then
        report("read " .. path .. ": " .. tostring(workspaces))
        return
    end
    store.workspaces = workspaces
end

---@param store LayoutStore
---@return string
function M.snapshot(store)
    local layouts = {}
    for _, strategy in ipairs(store.registry.layouts) do
        layouts[strategy.name] = { single_window = strategy.single_window == true }
    end
    return json.encode({ version = 1, layouts = layouts, workspaces = store.workspaces }) .. "\n"
end

-- A writer owns only IO state. Failed writes are reported and retried on the
-- next change; unchanged successful snapshots do not touch the filesystem.
---@param path string
---@param report PersistenceReporter
---@return PersistenceWriter
function M.writer(path, report)
    return { path = path, report = report, content = nil, error = nil }
end

---@param writer PersistenceWriter
---@param content string
---@return boolean
function M.write(writer, content)
    if writer.content == content then return true end
    local temporary = writer.path .. ".tmp"
    local file, err = io.open(temporary, "w")
    ---@type file*|boolean|nil
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
