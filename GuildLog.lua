-- GuildLog.lua
-- Captures guild log events with real timestamps and full actor names

GuildLog = {}
GuildLog.MAX_ENTRIES = 500  -- cap stored entries

-- Saved variable structure:
-- GuildLogDB = {
--   entries = { { timestamp, type, actor, target, rank, newRank } ... }
-- }

-- Event type constants
local EVENT_INVITE   = "INVITE"
local EVENT_REMOVE   = "REMOVE"    -- kicked or left
local EVENT_LEAVE    = "LEAVE"
local EVENT_PROMOTE  = "PROMOTE"
local EVENT_DEMOTE   = "DEMOTE"

-- Maps GuildLog event type → human label
local EVENT_LABELS = {
    [EVENT_INVITE]  = "Invited",
    [EVENT_REMOVE]  = "Removed",
    [EVENT_LEAVE]   = "Left",
    [EVENT_PROMOTE] = "Promoted",
    [EVENT_DEMOTE]  = "Demoted",
}

GuildLog.EVENT_LABELS = EVENT_LABELS

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function GetTimestamp()
    return time()  -- Unix epoch seconds
end

local function FormatTimestamp(t)
    return date("%Y-%m-%d %H:%M:%S", t)
end

GuildLog.FormatTimestamp = FormatTimestamp

local function AddEntry(entryType, actor, target, rank, newRank)
    if not GuildLogDB then return end

    local entry = {
        timestamp = GetTimestamp(),
        type      = entryType,
        actor     = actor or "",
        target    = target or "",
        rank      = rank or "",
        newRank   = newRank or "",
    }

    table.insert(GuildLogDB.entries, 1, entry)  -- newest first

    -- Trim to max
    while #GuildLogDB.entries > GuildLog.MAX_ENTRIES do
        table.remove(GuildLogDB.entries)
    end

    -- Notify UI if it's open
    if GuildLog.OnNewEntry then
        GuildLog.OnNewEntry(entry)
    end
end

-- ── Blizzard guild log parsing ───────────────────────────────────────────────
-- GUILD_EVENT_LOG_UPDATE fires whenever the server pushes a new event.
-- GetGuildEventInfo(i) returns:
--   eventType, player1, player2, newRankName, date (relative seconds offset)
--
-- We keep a "last seen count" so we only store genuinely new lines.

local lastSeenCount = 0

function GuildLog.ResetScanCount()
    lastSeenCount = 0
end

local function ScanGuildLog()
    local total = GetNumGuildEvents()
    if total == 0 then return end

    -- Only process entries newer than what we last saw
    local newCount = total - lastSeenCount
    if newCount <= 0 then
        lastSeenCount = total
        return
    end

    -- Iterate newest-first (index 1 = newest in Blizzard's API)
    for i = 1, newCount do
        local eventType, player1, player2, rankName, eventDate = GetGuildEventInfo(i)
        if eventType then
            if eventType == "invite" then
                -- player1 invited player2
                AddEntry(EVENT_INVITE, player1, player2, rankName)

            elseif eventType == "kick" then
                -- player1 kicked player2
                AddEntry(EVENT_REMOVE, player1, player2, rankName)

            elseif eventType == "leave" then
                -- player1 left (no actor)
                AddEntry(EVENT_LEAVE, nil, player1, rankName)

            elseif eventType == "promote" then
                -- player1 promoted player2 to rankName
                AddEntry(EVENT_PROMOTE, player1, player2, nil, rankName)

            elseif eventType == "demote" then
                -- player1 demoted player2 to rankName
                AddEntry(EVENT_DEMOTE, player1, player2, nil, rankName)
            end
        end
    end

    lastSeenCount = total
end

-- ── Frame & events ───────────────────────────────────────────────────────────

local frame = CreateFrame("Frame", "GuildLogFrame", UIParent)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("GUILD_EVENT_LOG_UPDATE")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")  -- join/leave guild

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "GuildLog" then
        -- Initialize saved variables
        if not GuildLogDB then
            GuildLogDB = { entries = {} }
        end
        if not GuildLogDB.entries then
            GuildLogDB.entries = {}
        end

        -- Request the guild event log from server
        GuildRequestMemberInfo()

        -- Slash command
        SLASH_GUILDLOG1 = "/glog"
        SLASH_GUILDLOG2 = "/guildlog"
        SlashCmdList["GUILDLOG"] = function(msg)
            msg = msg:lower():match("^%s*(.-)%s*$")
            if msg == "clear" then
                GuildLogDB.entries = {}
                lastSeenCount = 0
                print("|cff00ccff[GuildLog]|r Log cleared.")
            elseif msg == "debug" then
                print("|cff00ccff[GuildLog]|r Entries stored: " .. #GuildLogDB.entries)
            else
                GuildLogUI_Open()
            end
        end

        print("|cff00ccff[GuildLog]|r Loaded. Type |cffffff00/glog|r to open.")

    elseif event == "GUILD_EVENT_LOG_UPDATE" then
        ScanGuildLog()

    elseif event == "PLAYER_GUILD_UPDATE" then
        -- Reset when player changes guild
        lastSeenCount = 0
        C_GuildInfo.GuildRoster()  -- nudge server to send log
    end
end)
