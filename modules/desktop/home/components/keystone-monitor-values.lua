Name = "keystone-monitor-values"
NamePretty = "Monitor values"
Description = "Pick a monitor value"
Icon = "video-display"
HideFromProviderlist = true
Parent = "keystone-monitor-actions"
History = false
FixedOrder = true
Action = "keystone-monitor-menu dispatch '%VALUE%'"

local function json_decode(value)
    if jsonDecode ~= nil then
        return jsonDecode(value)
    end

    if jsonDecodes ~= nil then
        return jsonDecodes(value)
    end

    return nil
end

local function current_monitor()
    return lastMenuValue("keystone-monitors") or ""
end

local function current_action()
    return lastMenuValue("keystone-monitor-actions") or ""
end

function GetEntries()
    local monitor = current_monitor()
    local action = current_action()

    if monitor == "" or action == "" then
        return {}
    end

    local handle = io.popen(
        "keystone-monitor-menu monitor-values-json "
            .. "'" .. monitor:gsub("'", "'\\''") .. "' "
            .. "'" .. action:gsub("'", "'\\''") .. "' 2>/dev/null"
    )
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
