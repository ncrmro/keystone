Name = "keystone-project-details"
NamePretty = "Project details"
Description = "Project sessions and actions"
Icon = "folder-development"
HideFromProviderlist = true
Parent = "keystone-projects"
History = false
FixedOrder = true
Action = "keystone-project-menu dispatch '%VALUE%'"

local function json_decode(value)
    if jsonDecode ~= nil then
        return jsonDecode(value)
    end

    if jsonDecodes ~= nil then
        return jsonDecodes(value)
    end

    return nil
end

local function current_project()
    return lastMenuValue("keystone-projects") or ""
end

function GetEntries()
    local slug = current_project()

    if slug == "" then
        return {}
    end

    local handle = io.popen("keystone-project-menu project-details-json " .. "'" .. slug:gsub("'", "'\\''") .. "' 2>/dev/null")
    if not handle then
        return {}
    end

    local payload = handle:read("*a") or ""
    handle:close()

    if payload == "" then
        return {}
    end

    local ok, entries = pcall(json_decode, payload)
    if not ok or type(entries) ~= "table" then
        return {}
    end

    return entries
end
