-- GuildLog.lua
-- Guild event log with real timestamps, full actor names, and cross-client sync

GuildLog = LibStub("AceAddon-3.0"):NewAddon("GuildLog", "AceComm-3.0", "AceEvent-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")

GuildLog.MAX_ENTRIES = 0  -- 0 = unlimited

local COMM_PREFIX = "GuildLog"  -- must be <=16 chars
local SYNC_DELAY  = 5           -- seconds after login before requesting catch-up

-- == Event type constants =====================================================

local EVENT_INVITE  = "INVITE"
local EVENT_JOIN    = "JOIN"
local EVENT_REMOVE  = "REMOVE"
local EVENT_LEAVE   = "LEAVE"
local EVENT_PROMOTE = "PROMOTE"
local EVENT_DEMOTE  = "DEMOTE"

local EVENT_LABELS = {
    [EVENT_INVITE]  = "Invited",
    [EVENT_JOIN]    = "Joined",
    [EVENT_REMOVE]  = "Removed",
    [EVENT_LEAVE]   = "Left",
    [EVENT_PROMOTE] = "Promoted",
    [EVENT_DEMOTE]  = "Demoted",
}
GuildLog.EVENT_LABELS = EVENT_LABELS

local BLIZZARD_TO_EVENT = {
    invite  = EVENT_INVITE,
    join    = EVENT_JOIN,
    remove  = EVENT_REMOVE,
    quit    = EVENT_LEAVE,
    promote = EVENT_PROMOTE,
    demote  = EVENT_DEMOTE,
}

-- == Helpers ==================================================================

local function FormatTimestamp(t)
    return date("%Y-%m-%d %H:%M:%S", t)
end
GuildLog.FormatTimestamp = FormatTimestamp

-- Fuzzy dedup for Blizzard's replayed events.
-- Blizzard's offset is a truncated integer (hours), so the same event scanned at
-- two different login times that straddle an hour boundary produces approxTime
-- values that differ by exactly 3600 seconds.  The mathematical upper bound on
-- that drift is 7199 seconds (< 2 hours), so we use 7200 as the window.
-- Entries are newest-first; the break exits once we are past the match window.
local DEDUP_WINDOW = 7200
local function IsDuplicate(ourType, actor, target, approxTime)
    for _, e in ipairs(GuildLogDB.entries) do
        if e.timestamp < approxTime - DEDUP_WINDOW then break end
        if e.type   == ourType
           and e.actor  == (actor  or "")
           and e.target == (target or "")
           and math.abs(e.timestamp - approxTime) < DEDUP_WINDOW then
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

-- == Live event detection =====================================================
-- Architecture mirrors GRM exactly:
--   1. Plain-string substring check to identify which guild event fired.
--   2. WoW global string pattern to extract names/rank from the message.
--   3. IsInGuild() guard so no processing happens outside a guild.
-- The startup scan (GUILD_EVENT_LOG_UPDATE + QueryGuildEventLog) stays as the
-- catch-up pass for events that happened while offline.

-- Converts a WoW printf-style global string to a Lua extraction pattern.
-- "([%%S]+)" for player-name captures (WoW names have no spaces).
-- "(.+)"     for rank-name captures (rank names may contain spaces).
local function MakePattern(fmt, capture)
    return fmt:gsub("%%s", capture)
end

-- Pre-built extraction patterns; populated once in OnEnable.
local pat_join    -- extracts the joining player name
local pat_kick    -- extracts kicked player + kicker  (ERR_GUILD_REMOVE_SS order)
local pat_promote -- extracts officer, player, new rank
local pat_demote

local function BuildLivePatterns()
    pat_join    = MakePattern(ERR_GUILD_JOIN_S,      "([%%S]+)")
    pat_kick    = MakePattern(ERR_GUILD_REMOVE_SS,   "([%%S]+)")
    pat_promote = MakePattern(ERR_GUILD_PROMOTE_SSS, "(.+)")
    pat_demote  = MakePattern(ERR_GUILD_DEMOTE_SSS,  "(.+)")
end

-- Scan the roster for a joining member's rank (~1 s after join to let roster update).
local function FindMemberRank(name)
    local count = GetNumGuildMembers()
    for i = 1, count do
        local fullName, rankName = GetGuildRosterInfo(i)
        if fullName then
            local shortName = fullName:match("^([^%-]+)")
            if shortName == name or fullName == name then
                return rankName or ""
            end
        end
    end
    return ""
end

local function HandleLiveGuildEvent(_, message)
    if not GuildLogDB or not IsInGuild() then return end
    local now = time()

    if message:find("joined the guild.", 1, true) then
        local name = message:match(pat_join)
        if not name then return end
        C_GuildInfo.GuildRoster()
        QueryGuildEventLog()
        C_Timer.After(1, function()
            if IsDuplicate(EVENT_JOIN, name, "", now) then return end
            AddEntry(EVENT_JOIN, name, "", FindMemberRank(name), "", now)
        end)

    elseif message:find("left the guild.", 1, true) then
        -- GRM extracts leave name as first word (everything before the first space)
        local name = message:sub(1, (message:find(" ", 1, true) or 2) - 1)
        if name == "" then return end
        C_GuildInfo.GuildRoster()
        QueryGuildEventLog()
        if not IsDuplicate(EVENT_LEAVE, name, "", now) then
            AddEntry(EVENT_LEAVE, name, "", "", "", now)
        end

    elseif message:find("has been kicked", 1, true) then
        local kicked, kicker = message:match(pat_kick)
        if not kicked then return end
        C_GuildInfo.GuildRoster()
        QueryGuildEventLog()
        if not IsDuplicate(EVENT_REMOVE, kicked, "", now) then
            AddEntry(EVENT_REMOVE, kicker, kicked, "", "", now)
        end

    elseif message:find("has promoted", 1, true) then
        local officer, target, rank = message:match(pat_promote)
        if not officer then return end
        if not IsDuplicate(EVENT_PROMOTE, officer, target, now) then
            AddEntry(EVENT_PROMOTE, officer, target, "", rank, now)
        end

    elseif message:find("has demoted", 1, true) then
        local officer, target, rank = message:match(pat_demote)
        if not officer then return end
        if not IsDuplicate(EVENT_DEMOTE, officer, target, now) then
            AddEntry(EVENT_DEMOTE, officer, target, "", rank, now)
        end
    end
end

-- == Blizzard guild log scan ==================================================
-- GUILD_EVENT_LOG_UPDATE fires when the server pushes events.
-- Blizzard replays the last 20 events on every login; the signature watermark
-- prevents rescanning the same event list twice in a session.

-- Signature of Blizzard's i=1 event at the end of the last scan.
-- Resets to nil each session so a fresh relog always does a full retroactive scan.
local lastScanSig = nil

local function GetEventSig(i)
    local et, p1, p2 = GetGuildEventInfo(i)
    return (et or "") .. "\0" .. (p1 or "") .. "\0" .. (p2 or "")
end

local function ScanGuildLog()
    if not GuildLogDB then return 0 end
    local total = GetNumGuildEvents()
    if total == 0 then return 0 end
    local now = time()
    local added = 0

    local currentSig = GetEventSig(1)

    -- Determine how far back to scan.
    -- nil lastScanSig  => first scan this session, process all 20 events.
    -- matching sig     => nothing new, skip entirely.
    -- changed sig      => find the old watermark in the list and process only the new events above it.
    local startFrom = total
    if lastScanSig ~= nil then
        if currentSig == lastScanSig then return end
        for i = 1, total do
            if GetEventSig(i) == lastScanSig then
                startFrom = i - 1
                break
            end
        end
        -- If old sig fell off the 20-event log, startFrom stays at total (scan all).
    end

    for i = startFrom, 1, -1 do
        local eventType, player1, player2, rankName, year, month, day, hour = GetGuildEventInfo(i)
        local ourType = eventType and BLIZZARD_TO_EVENT[eventType]
        if ourType then
            -- WoW logs two entries per invite+accept: one "invite" with player2=invitee
            -- and one "invite" with player2=nil (the acceptance notification).  The join
            -- itself is captured via the separate "join" event type; skip the empty-target
            -- invite to avoid an "(unknown)" duplicate.
            local skip = (ourType == EVENT_INVITE and (player2 == nil or player2 == ""))
                      or (ourType == EVENT_LEAVE  and (player1 == nil or player1 == ""))
            if not skip then
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
                    added = added + 1
                end
            end
        end
    end

    lastScanSig = currentSig
    return added
end

-- Forces a full re-scan of Blizzard's guild event log from scratch.
-- Called by the Refresh button, and implicitly after Clear Log.
-- Resets the watermark so ScanGuildLog processes all 20 events on the next
-- GUILD_EVENT_LOG_UPDATE, then requests fresh data from the server.
function GuildLog.ForceRescan()
    lastScanSig = nil
    C_GuildInfo.GuildRoster()
    QueryGuildEventLog()
end

-- == Startup dedup cleanup ====================================================
-- 1. Drops INVITE entries with an empty target -- these are the spurious join
--    notifications WoW logs alongside the real invite; proper "join" events are
--    now captured via the EVENT_JOIN type instead.
-- 2. Removes time-based duplicates (same type/actor/target within 3600 s) that
--    accumulated before the 7200-second IsDuplicate window was introduced.
-- Safe to run every load -- idempotent once the log is clean.

local function PurgeExistingDuplicates()
    local entries = GuildLogDB.entries
    local before = #entries
    if before < 2 then return end

    table.sort(entries, function(a, b) return a.timestamp > b.timestamp end)

    local kept   = {}
    local byKey  = {}  -- "type\1actor\1target" -> list of kept timestamps
    for _, e in ipairs(entries) do
        local skip = (e.type == "LEAVE"  and (e.actor  == nil or e.actor  == ""))
                  or (e.type == "INVITE" and (e.target == nil or e.target == ""))
        if not skip then
            local key   = (e.type or "") .. "\1" .. (e.actor or "") .. "\1" .. (e.target or "")
            local times = byKey[key]
            local isDup = false
            if times then
                for _, t in ipairs(times) do
                    if math.abs(t - e.timestamp) <= 3600 then
                        isDup = true
                        break
                    end
                end
            end
            if not isDup then
                kept[#kept + 1] = e
                if not byKey[key] then byKey[key] = {} end
                local ts = byKey[key]
                ts[#ts + 1] = e.timestamp
            end
        end
    end

    local removed = before - #kept
    if removed > 0 then
        GuildLogDB.entries = kept
        print(string.format("|cff00ccff[GuildLog]|r Cleaned up %d duplicate %s.",
            removed, removed == 1 and "entry" or "entries"))
    end
end

-- == AceAddon lifecycle =======================================================

function GuildLog:OnInitialize()
    GuildLogDB = GuildLogDB or {}
    GuildLogDB.entries = GuildLogDB.entries or {}
    PurgeExistingDuplicates()

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
    BuildLivePatterns()
    self:RegisterEvent("CHAT_MSG_SYSTEM", HandleLiveGuildEvent)

    -- Debounce GUILD_EVENT_LOG_UPDATE: WoW fires it multiple times in rapid succession
    -- on login.  Collapsing the burst ensures a single consistent `now` for the scan.
    -- loginScanDone gates the one-time login summary message so it only prints once.
    local scanTimer = nil
    local loginScanDone = false
    local function DebouncedScan()
        if scanTimer then scanTimer:Cancel() end
        scanTimer = C_Timer.NewTimer(0.5, function()
            scanTimer = nil
            local added = ScanGuildLog()
            if not loginScanDone then
                loginScanDone = true
                if added > 0 then
                    print(string.format(
                        "|cff00ccff[GuildLog]|r Startup scan complete -- %d new %s since last session.",
                        added, added == 1 and "event" or "events"))
                else
                    print("|cff00ccff[GuildLog]|r Startup scan complete -- no new events.")
                end
            end
        end)
    end
    self:RegisterEvent("GUILD_EVENT_LOG_UPDATE", DebouncedScan)
    self:RegisterEvent("PLAYER_GUILD_UPDATE", function()
        C_GuildInfo.GuildRoster()
    end)

    -- Request guild event log data from the server on login so
    -- GUILD_EVENT_LOG_UPDATE fires and ScanGuildLog picks up offline events.
    -- Without this explicit request the event never fires automatically.
    C_Timer.After(2, function()
        QueryGuildEventLog()
    end)

    -- Intercept Blizzard's guild log frame so "View Log" opens our UI instead.
    -- allowNativeLog bypasses the redirect for one show (used by the UI button).
    local allowNativeLog = false
    GuildLog.OpenNativeLog = function()
        if CommunitiesGuildLogFrame then
            allowNativeLog = true
            CommunitiesGuildLogFrame:Show()
        else
            print("|cff00ccff[GuildLog]|r Blizzard guild log is not available yet.")
        end
    end

    -- CommunitiesGuildLogFrame may be nil when Blizzard_Communities first loads if it is
    -- created lazily.  Poll until it exists, then register the OnShow hook exactly once.
    -- The hide is deferred one frame so CommunitiesFrame finishes its own show cycle
    -- before we interrupt it; calling Hide() synchronously inside OnShow was causing
    -- GuildLog to open and immediately close (invisible to the user on the first click).
    local guildLogFrameHooked = false
    local function TryHookGuildLogFrame()
        if guildLogFrameHooked or not CommunitiesGuildLogFrame then return end
        guildLogFrameHooked = true

        CommunitiesGuildLogFrame:HookScript("OnShow", function(_frame)
            if allowNativeLog then
                allowNativeLog = false
                return
            end
            C_Timer.After(0, function()
                if GuildLogUI_IsOpen() then return end
                -- Hide CommunitiesFrame (parent) via HideUIPanel rather than hiding
                -- CommunitiesGuildLogFrame (child) directly. Hiding the child bypasses
                -- CommunitiesFrame's internal state machine, leaving it open in a broken
                -- state where ESC is consumed every press but CommunitiesFrame never closes.
                if CommunitiesFrame and CommunitiesFrame:IsShown() then
                    HideUIPanel(CommunitiesFrame)
                end
                GuildLogUI_Open()
            end)
        end)
    end

    EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", function()
        local attempts = 0
        local function Poll()
            TryHookGuildLogFrame()
            if not guildLogFrameHooked then
                attempts = attempts + 1
                if attempts < 50 then
                    C_Timer.After(0.1, Poll)
                end
            end
        end
        Poll()
    end)

    C_GuildInfo.GuildRoster()

    -- Wait for the guild channel to be connected before requesting catch-up
    C_Timer.After(SYNC_DELAY, function()
        self:SendSyncRequest()
    end)
end

-- == Sync protocol ============================================================
--
-- On login this client broadcasts REQ to the GUILD channel with its newest
-- timestamp. Every online member with the addon whispers back DATA containing
-- any entries newer than that timestamp. Multiple responders is fine --
-- IsSyncDuplicate prevents double-inserts.
--
-- AceComm-3.0 handles chunking automatically, so large histories are safe.

function GuildLog:SendSyncRequest()
    local since = GuildLogDB.entries[1] and GuildLogDB.entries[1].timestamp or 0
    local payload = AceSerializer:Serialize({ t = "REQ", since = since })
    self:SendCommMessage(COMM_PREFIX, payload, "GUILD")
end

function GuildLog:OnCommReceived(_prefix, payload, _distribution, sender)
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
