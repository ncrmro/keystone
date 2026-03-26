Name = "keystone-project-session"
NamePretty = "Project session"
Description = "Type a session slug, then press Enter"
Icon = "folder-development"
HideFromProviderlist = true
History = false
FixedOrder = true

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
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

Actions = {
    create_session = "lua:CreateSession",
}

function GetEntries()
    local slug = current_project()
    if slug == "" then
        return {}
    end

    return {
        {
            Text = "Create session",
            Subtext = "Project: " .. slug .. " · leave empty for main",
            Value = slug,
            Preview = "keystone-project-menu preview " .. shell_quote(slug),
            PreviewType = "command",
            Actions = {
                create_session = "lua:CreateSession",
            },
        }
    }
end

function CreateSession(value, args, query)
    local session = query or ""
    if session == "" then
        session = "main"
    end

    os.execute("keystone-project-menu open " .. shell_quote(value) .. " " .. shell_quote(session) .. " >/dev/null 2>&1 &")
end
