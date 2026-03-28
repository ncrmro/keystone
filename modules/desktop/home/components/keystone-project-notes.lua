Name = "keystone-project-notes"
NamePretty = "Project notes"
Description = "Project-scoped notes"
Icon = "notes"
HideFromProviderlist = true
Parent = "keystone-project-details"
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
    local handle = io.popen("keystone-project-menu get-current-project")
    if not handle then
        return ""
    end

    local slug = handle:read("*l") or ""
    handle:close()
    return slug
end

function GetEntries()
    local slug = current_project()

    if slug == "" then
        return {}
    end

    local handle = io.popen("keystone-project-menu project-notes-json " .. "'" .. slug:gsub("'", "'\\''") .. "' 2>/dev/null")
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
