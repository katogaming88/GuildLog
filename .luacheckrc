std = "lua51"

-- Ignore line length — WoW color-code strings get long
max_line_length = false

-- Addon globals defined across both files
globals = {
    -- Addon
    "GuildLog",
    "GuildLogUI",
    "GuildLogDB",
    "GuildLogUI_Open",
    "GuildLogUI_IsOpen",

    -- Named frames (registered with WoW by string name)
    "GuildLogFrame",
    "GuildLogMainFrame",
    "GuildLogScrollBar",
    "GuildLogSearch",

    -- Ace3 / LibStub
    "LibStub",

    -- WoW UI API
    "CreateFrame",
    "UnitName",
    "UIParent",
    "UISpecialFrames",
    "StaticPopupDialogs",
    "StaticPopup_Show",

    -- WoW timer API
    "C_Timer",

    -- WoW guild API
    "GetNumGuildEvents",
    "GetGuildEventInfo",
    "GuildRequestMemberInfo",
    "C_GuildInfo",
    "C_Timer",
    "UnitName",

    -- WoW Communities / guild pane
    "EventUtil",
    "CommunitiesGuildLogFrame",

    -- Ace3 / LibStub
    "LibStub",

    -- WoW slash command system
    "SlashCmdList",
    "SLASH_GUILDLOG1",
    "SLASH_GUILDLOG2",

    -- WoW Lua overrides / additions (not in standard lua51 std)
    "date",
    "time",
    "wipe",
    "tinsert",
    "tremove",
    "strsplit",
    "strfind",
    "strmatch",
    "format",
}

-- Ignore warnings about unused loop variables named _
unused_args = true
self = false
