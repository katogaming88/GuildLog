-- GuildLog.lua
-- Guild event log with real timestamps, full actor names, and cross-client sync

GuildLog = LibStub("AceAddon-3.0"):NewAddon("GuildLog", "AceComm-3.0", "AceEvent-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")

GuildLog.MAX_ENTRIES = 0  -- 0 = unlimited

local COMM_PREFIX = "GuildLog"  -- must be ≤16 chars
local SYNC_DELAY  = 5           -- seconds after login before requesting catch-up

-- ── Event type constants ──────────────────────────────────────────────────────

local EVENT_INVITE  = "INVITE"
local EVENT_REMOVE  = "REMOVE"
local EVENT_LEAVE   = "LEAVE"
local EVENT_PROMOTE = "PROMOTE"
local EVENT_DEMOTE  = "DEMOTE"

local EVENT_LABELS = {
    [EVENT_INVITE]  = "Invited",
    [EVENT_REMOVE]  = "Removed",
    [EVENT_LEAVE]   = "Left",
    [EVENT_PROMOTE] = "Promoted",
    [EVENT_DEMOTE]  = "Demoted",
}
GuildLog.EVENT_LABELS = EVENT_LABELS

local BLIZZARD_TO_EVENT = {
    invite  = EVENT_INVITE,
    kick    = EVENT_REMOVE,
    leave   = EVENT_LEAVE,
    promote = EVENT_PROMOTE,
    demote  = EVENT_DEMOTE,
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function FormatTimestamp(t)
    return date("%Y-%m-%d %H:%M:%S", t)
end
GuildLog.FormatTimestamp = FormatTimestamp

-- Fuzzy dedup for Blizzard's replayed events (absorbs clock drift on login)
local function IsDuplicate(ourType, actor, target, approxTime)
    local limit = math.min(60, #GuildLogDB.entries)
    for i = 1, limit do
        local e = GuildLogDB.entries[i]
        if e.type   == ourType
           and e.actor  == (actor  or "")
           and e.target == (target or "")
           and math.abs(e.timestamp - approxTime) < 60 then
            return true
        end
    end
    return false
end

-- Exact dedup for entries arriving over the sync channel
local function IsSyncDuplicate(entry)
    for _, e in ipairs(GuildLogDB.entries) do
        if e.timestamp == entry.timestamp
           and e.type   == entry.type
           and e.actor  == entry.actor
           and e.target == entry.target then
            return true
        end
    end
    return false
end

local function AddEntry(entryType, actor, target, rank, newRank, timestamp)
    if not GuildLogDB then return end
    local entry = {
        timestamp = timestamp or time(),
        type      = entryType,
        actor     = actor   or "",
        target    = target  or "",
        rank      = rank    or "",
        newRank   = newRank or "",
    }
    table.insert(GuildLogDB.entries, 1, entry)
    if GuildLog.MAX_ENTRIES > 0 then
        while #GuildLogDB.entries > GuildLog.MAX_ENTRIES do
            table.remove(GuildLogDB.entries)
        end
    end
    if GuildLog.OnNewEntry then GuildLog.OnNewEntry(entry) end
end

-- Inserts a sync'd entry at the correct newest-first position
local function InsertEntryOrdered(entry)
    local inserted = false
    for i, e in ipairs(GuildLogDB.entries) do
        if entry.timestamp >= e.timestamp then
            table.insert(GuildLogDB.entries, i, entry)
            inserted = true
            break
        end
    end
    if not inserted then
        table.insert(GuildLogDB.entries, entry)
    end
    if GuildLog.MAX_ENTRIES > 0 then
        while #GuildLogDB.entries > GuildLog.MAX_ENTRIES do
            table.remove(GuildLogDB.entries)
        end
    end
end

-- ── Blizzard guild log scan ───────────────────────────────────────────────────
-- GUILD_EVENT_LOG_UPDATE fires when the server pushes events.
-- Blizzard replays the last 20 events on every login; IsDuplicate filters those.

local function ScanGuildLog()
    if not GuildLogDB then return end
    local total = GetNumGuildEvents()
    if total == 0 then return end
    local now = time()
    for i = total, 1, -1 do
        local eventType, player1, player2, rankName, year, month, day, hour = GetGuildEventInfo(i)
        local ourType = eventType and BLIZZARD_TO_EVENT[eventType]
        if ourType then
            -- GetGuildEventInfo returns offsets: years/months/days/hours ago.
            -- Subtract them from today's date using date("*t") so calendar arithmetic is correct.
            local d = date("*t", now)
            d.year  = d.year  - (year  or 0)
            d.month = d.month - (month or 0)
            d.day   = d.day   - (day   or 0)
            d.hour  = d.hour  - (hour  or 0)
            d.min   = 0
            d.sec   = 0
            local approxTime = time(d)
            if not IsDuplicate(ourType, player1, player2, approxTime) then
                local rank, newRank
                if ourType == EVENT_PROMOTE or ourType == EVENT_DEMOTE then
                    newRank = rankName
                else
                    rank = rankName
                end
                AddEntry(ourType, player1, player2, rank, newRank, approxTime)
            end
        end
    end
end

-- ── AceAddon lifecycle ────────────────────────────────────────────────────────

function GuildLog:OnInitialize()
    GuildLogDB = GuildLogDB or {}
    GuildLogDB.entries = GuildLogDB.entries or {}

    self:RegisterComm(COMM_PREFIX)

    SLASH_GUILDLOG1 = "/glog"
    SLASH_GUILDLOG2 = "/guildlog"
    SlashCmdList["GUILDLOG"] = function(msg)
        msg = msg:lower():match("^%s*(.-)%s*$")
        if msg == "clear" then
            GuildLogDB.entries = {}
            print("|cff00ccff[GuildLog]|r Log cleared.")
        elseif msg == "debug" then
            print("|cff00ccff[GuildLog]|r Entries stored: " .. #GuildLogDB.entries)
        else
            GuildLogUI_Open()
        end
    end

    print("|cff00ccff[GuildLog]|r Loaded. Type |cffffff00/glog|r to open.")
end

function GuildLog:OnEnable()
    self:RegisterEvent("GUILD_EVENT_LOG_UPDATE", ScanGuildLog)
    self:RegisterEvent("PLAYER_GUILD_UPDATE", function()
        C_GuildInfo.GuildRoster()
    end)

    C_GuildInfo.GuildRoster()

    -- Wait for the guild channel to be connected before requesting catch-up
    C_Timer.After(SYNC_DELAY, function()
        self:SendSyncRequest()
    end)
end

-- ── Sync protocol ─────────────────────────────────────────────────────────────
--
-- On login this client broadcasts REQ to the GUILD channel with its newest
-- timestamp. Every online member with the addon whispers back DATA containing
-- any entries newer than that timestamp. Multiple responders is fine —
-- IsSyncDuplicate prevents double-inserts.
--
-- AceComm-3.0 handles chunking automatically, so large histories are safe.

function GuildLog:SendSyncRequest()
    local since = GuildLogDB.entries[1] and GuildLogDB.entries[1].timestamp or 0
    local payload = AceSerializer:Serialize({ t = "REQ", since = since })
    self:SendCommMessage(COMM_PREFIX, payload, "GUILD")
end

function GuildLog:OnCommReceived(prefix, payload, distribution, sender)
    if sender == UnitName("player") then return end
    local ok, data = AceSerializer:Deserialize(payload)
    if not ok or type(data) ~= "table" then return end

    if data.t == "REQ" then
        self:HandleSyncRequest(data.since, sender)
    elseif data.t == "DATA" then
        self:HandleSyncData(data.entries)
    end
end

function GuildLog:HandleSyncRequest(since, sender)
    if type(since) ~= "number" then return end
    local toSend = {}
    for _, entry in ipairs(GuildLogDB.entries) do
        if entry.timestamp > since then
            toSend[#toSend + 1] = entry
        else
            break  -- entries are newest-first; nothing further can qualify
        end
    end
    if #toSend == 0 then return end

    local payload = AceSerializer:Serialize({ t = "DATA", entries = toSend })
    self:SendCommMessage(COMM_PREFIX, payload, "WHISPER", sender)
end

function GuildLog:HandleSyncData(entries)
    if type(entries) ~= "table" then return end
    local added = 0
    for _, entry in ipairs(entries) do
        if type(entry) == "table"
           and type(entry.timestamp) == "number"
           and type(entry.type) == "string"
           and not IsSyncDuplicate(entry) then
            entry.actor   = entry.actor   or ""
            entry.target  = entry.target  or ""
            entry.rank    = entry.rank    or ""
            entry.newRank = entry.newRank or ""
            InsertEntryOrdered(entry)
            added = added + 1
        end
    end
    if added > 0 and GuildLog.OnNewEntry then
        GuildLog.OnNewEntry(nil)  -- signal UI to refresh
    end
end
