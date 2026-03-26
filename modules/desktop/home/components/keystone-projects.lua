Name = "keystone-projects"
NamePretty = "Projects"
Description = "Project switcher"
Icon = "folder-development"
HideFromProviderlist = true
SearchName = true
History = true
HistoryWhenEmpty = true
FixedOrder = true

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function GetEntries()
    local entries = {}
    -- Bulk load all project data in one pass to avoid N+1 bottleneck
    local handle = io.popen("pz export-menu-data 2>/dev/null")
    if not handle then
        return entries
    end

    for line in handle:lines() do
        -- Format: slug \t summary \t mission
        local slug, summary, mission = line:match("([^\t]+)\t([^\t]+)\t(.*)")
        if slug then
            local quoted = shell_quote(slug)
            table.insert(entries, {
                Text = slug,
                Subtext = summary,
                Value = slug,
                Submenu = "keystone-project-details",
                Preview = "keystone-project-menu preview " .. quoted,
                PreviewType = "command",
                Actions = {
                    open_main = "keystone-project-menu open " .. quoted,
                    new_session_menu = "keystone-project-menu open-session-menu " .. quoted,
                },
            })
        end
    end

    handle:close()
    return entries
end
