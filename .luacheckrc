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
    "GetNumGuildMembers",
    "GetGuildRosterInfo",
    "QueryGuildEventLog",
    "IsInGuild",
    "GuildRequestMemberInfo",
    "C_GuildInfo",
    "C_Timer",
    "UnitName",

    -- WoW global format strings used for pattern building
    "ERR_GUILD_JOIN_S",
    "ERR_GUILD_REMOVE_SS",
    "ERR_GUILD_PROMOTE_SSS",
    "ERR_GUILD_DEMOTE_SSS",

    -- WoW Communities / guild pane
    "EventUtil",
    "CommunitiesGuildLogFrame",
    "CommunitiesFrame",
    "HideUIPanel",

    -- Ace3 / LibStub
    "LibStub",

    -- WoW slash command system
    "SlashCmdList",
    "SLASH_GUILDLOG1",
    "SLASH_GUILDLOG2",

    -- WoW addon profiling API (/glog stats)
    "UpdateAddOnMemoryUsage",
    "GetAddOnMemoryUsage",
    "UpdateAddOnCPUUsage",
    "GetAddOnCPUUsage",
    "GetCVar",

    -- WoW input state
    "IsShiftKeyDown",
    "GetCursorPosition",

    -- WoW shared font templates
    "GameFontDisable",
    "GameFontHighlight",
    "GameFontNormal",
    "GameFontNormalLarge",

    -- WoW Lua overrides / additions (not in standard lua51 std)
    "issecretvalue",
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
