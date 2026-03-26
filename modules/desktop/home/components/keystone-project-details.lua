Name = "keystone-project-details"
NamePretty = "Project details"
Description = "Project sessions and actions"
Icon = "folder-development"
HideFromProviderlist = true
Parent = "keystone-projects"
History = false
FixedOrder = true

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function current_project()
    return lastMenuValue("keystone-projects") or ""
end

function GetEntries()
    local entries = {}
    local slug = current_project()

    if slug == "" then
        return entries
    end

    local quoted = shell_quote(slug)
    local preview = "keystone-project-menu preview " .. quoted

    table.insert(entries, {
        Text = "Open main session",
        Subtext = "Focus or launch the main project session",
        Value = slug,
        Preview = preview,
        PreviewType = "command",
        Actions = {
            open_session = "keystone-project-menu open " .. quoted .. " main",
        },
    })

    table.insert(entries, {
        Text = "New session",
        Subtext = "Type a new slug in the next step",
        Value = slug,
        Preview = preview,
        PreviewType = "command",
        Actions = {
            new_session_menu = "keystone-project-menu open-session-menu " .. quoted,
        },
    })

    local handle = io.popen("keystone-project-menu sessions " .. quoted)
    if handle then
        for line in handle:lines() do
            local session, workspace = line:match("([^\t]+)\t(.+)")
            if session and session ~= "main" then
                table.insert(entries, {
                    Text = session,
                    Subtext = workspace,
                    Value = slug,
                    Preview = preview,
                    PreviewType = "command",
                    Actions = {
                        open_session = "keystone-project-menu open " .. quoted .. " " .. shell_quote(session),
                    },
                })
            end
        end
        handle:close()
    end

    return entries
end
