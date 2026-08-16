-- GuildLog.lua
-- Guild event log with real timestamps, full actor names, and cross-client sync

GuildLog = LibStub("AceAddon-3.0"):NewAddon("GuildLog", "AceComm-3.0", "AceEvent-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")

GuildLog.MAX_ENTRIES = 0  -- 0 = unlimited

local COMM_PREFIX = "GuildLog"  -- must be <=16 chars
local SYNC_DELAY  = 5           -- seconds after login before requesting catch-up

-- Blizzard only appends "-Realm" to a name when it's needed to disambiguate,
-- and GetGuildRosterInfo(), GetGuildEventInfo(), and CHAT_MSG_SYSTEM text
-- don't always agree on whether a given moment counts as ambiguous. That's a
-- real problem for two different reasons that pull in opposite directions:
--   1. The same player can look like two different people if one source
--      hands back "Tt" and another hands back "Tt-Detheroc" for them.
--   2. Two different players *can* legitimately share a short name across
--      realms (e.g. "Katorri-Stormrage" and "Katorri-Medivh" in the same
--      guild) -- collapsing both down to bare "Katorri" would merge two
--      real people into one.
-- The fix for (1) must never cause (2). So nothing is ever matched or stored
-- by short name alone. Instead, nameIndex[short] tracks every realm-qualified
-- form actually seen for that short name. A bare name only gets upgraded to
-- a full one when exactly one realm has ever been seen for it -- genuine
-- ambiguity (2+ realms on record) leaves it bare rather than guessing, since
-- a wrong guess silently misattributes one player's event to another.
local function ShortName(name)
    if not name or name == "" then return name end
    return name:match("^([^%-]+)") or name
end

-- Remembers the realm-qualified form of a name whenever one is seen.
local function RememberDisplayName(name)
    if not GuildLogDB or not name or name == "" then return end
    local short = ShortName(name)
    if name ~= short then
        GuildLogDB.nameIndex = GuildLogDB.nameIndex or {}
        local set = GuildLogDB.nameIndex[short]
        if not set then
            set = {}
            GuildLogDB.nameIndex[short] = set
        end
        set[name] = true
    end
end

-- Turns any name (bare or realm-qualified) into the best realm-qualified form
-- available, for storage/display and for matching. A realm-qualified input is
-- always trusted as-is (that source explicitly disambiguated). A bare input
-- is upgraded to the one realm-qualified form on record for it, if there's
-- only one; genuinely ambiguous short names (2+ realms on record) are left
-- bare rather than guessed. A short name never before seen with a realm
-- defaults to the player's own realm, since Blizzard only omits the suffix
-- when there's no ambiguity to resolve, which in practice means "shares your
-- realm" for the overwhelming majority of guildmates it applies to.
local function ResolveDisplayName(name)
    if not name or name == "" then return name end
    local short = ShortName(name)
    if name ~= short then
        RememberDisplayName(name)
        return name
    end

    local set = GuildLogDB and GuildLogDB.nameIndex and GuildLogDB.nameIndex[short]
    if set then
        local only, count = nil, 0
        for full in pairs(set) do
            only = full
            count = count + 1
            if count > 1 then break end
        end
        if count == 1 then return only end
        if count > 1 then return short end  -- genuinely ambiguous -- don't guess
    end

    -- Best-effort display guess for a short name with no confirmed realm on
    -- record yet -- deliberately NOT remembered via RememberDisplayName(). If
    -- this guess were persisted as a "seen" sighting and the real (possibly
    -- different) realm later arrived from a trusted source, the two would
    -- coexist in the index as false ambiguity, and worse, anything that used
    -- this resolved value as a stable key (e.g. the roster-snapshot diff)
    -- would see the key change out from under it and record a spurious
    -- leave+rejoin for a player who never actually left. Recomputing the
    -- guess fresh each call keeps it deterministic without that side effect.
    local realm = GetNormalizedRealmName()
    if realm and realm ~= "" then
        return short .. "-" .. realm
    end
    return short
end

-- Stable key for matching/comparing two mentions of the same player --
-- deliberately NOT the same value ResolveDisplayName() returns. That display
-- name can legitimately change mid-session (a short name's realm goes from
-- "guessed" to "confirmed" the first time a trusted source hands back the
-- suffixed form), and anything that compared by the resolved value directly
-- would see two mentions of the *same* person as different once that
-- resolution changed -- e.g. Blizzard's event log gets rescanned from
-- scratch on every login, so an entry logged under a guessed identity last
-- session can fail to match against this session's now-confirmed identity
-- and get relogged as new. The short name is stable across all of that
-- unless it's genuinely ambiguous (2+ confirmed realms on record for it), in
-- which case only the full name can keep two real players apart.
local function MatchKey(name)
    local short = ShortName(name)
    local set = GuildLogDB and GuildLogDB.nameIndex and GuildLogDB.nameIndex[short]
    local count = 0
    if set then
        for _ in pairs(set) do
            count = count + 1
            if count > 1 then break end
        end
    end
    if count > 1 then return ResolveDisplayName(name) end
    return short
end

-- == Event type constants =====================================================

local EVENT_INVITE  = "INVITE"
local EVENT_JOIN    = "JOIN"
local EVENT_REMOVE  = "REMOVE"
local EVENT_LEAVE   = "LEAVE"
local EVENT_PROMOTE = "PROMOTE"
local EVENT_DEMOTE  = "DEMOTE"
local EVENT_NOTE    = "NOTE"
local EVENT_ONOTE   = "ONOTE"

local EVENT_LABELS = {
    [EVENT_INVITE]  = "Invited",
    [EVENT_JOIN]    = "Joined",
    [EVENT_REMOVE]  = "Removed",
    [EVENT_LEAVE]   = "Left",
    [EVENT_PROMOTE] = "Promoted",
    [EVENT_DEMOTE]  = "Demoted",
    [EVENT_NOTE]    = "Note changed",
    [EVENT_ONOTE]   = "Officer note changed",
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
    return date("%m/%d/%y %I:%M %p", t)
end
GuildLog.FormatTimestamp = FormatTimestamp

-- Fuzzy dedup for Blizzard's replayed events.
-- Blizzard's offset is a truncated integer (hours), so the same event scanned at
-- two different login times that straddle an hour boundary produces approxTime
-- values that differ by exactly 3600 seconds.  The mathematical upper bound on
-- that drift is 7199 seconds (< 2 hours), so we use 7200 as the window.
-- Entries are newest-first; the break exits once we are past the match window.
local DEDUP_WINDOW = 7200
-- actor/target are each treated as a wildcard when either side is "" --
-- the roster-snapshot backup scan (see below) doesn't know who performed a
-- kick/promote/demote, only that it happened, so it records actor="" and
-- still needs to match/be matched against the real actor name the live or
-- log scan recorded for the same event. Likewise a JOIN's target holds the
-- inviter when known (see ScanGuildLog): a live-detected join (target="")
-- and the same join later confirmed via Blizzard's log (target=officer)
-- must still be recognized as the same event.
-- Returns the matching entry (or nil), so callers can also use it to backfill
-- a field discovered later -- see the JOIN inviter backfill in ScanGuildLog.
local function FindDuplicate(ourType, actor, target, approxTime)
    -- Compare by MatchKey, not the stored/resolved value directly -- see
    -- MatchKey's comment for why: two mentions of the same player can be
    -- stored under different resolved forms if the realm resolution changed
    -- between when each was written.
    local actorKey  = actor  ~= "" and MatchKey(actor)  or ""
    local targetKey = target ~= "" and MatchKey(target) or ""
    for _, e in ipairs(GuildLogDB.entries) do
        if e.timestamp < approxTime - DEDUP_WINDOW then break end
        local eActorKey  = e.actor  ~= "" and MatchKey(e.actor)  or ""
        local eTargetKey = e.target ~= "" and MatchKey(e.target) or ""
        if e.type   == ourType
           and (eActorKey  == actorKey  or eActorKey  == "" or actorKey  == "")
           and (eTargetKey == targetKey or eTargetKey == "" or targetKey == "")
           and math.abs(e.timestamp - approxTime) < DEDUP_WINDOW then
            return e
        end
    end
    return nil
end

local function IsDuplicate(ourType, actor, target, approxTime)
    return FindDuplicate(ourType, actor, target, approxTime) ~= nil
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
        actor     = ResolveDisplayName(actor)  or "",
        target    = ResolveDisplayName(target) or "",
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
    local key = MatchKey(name)
    local count = GetNumGuildMembers()
    for i = 1, count do
        local fullName, rankName = GetGuildRosterInfo(i)
        if fullName and MatchKey(fullName) == key then
            return rankName or ""
        end
    end
    return ""
end

-- Finds a player's most recently known rank strictly before `beforeTime`, by
-- scanning their own history: their starting rank from JOIN, or their rank
-- after their most recent PROMOTE/DEMOTE, whichever is more recent. Backfills
-- an old rank Blizzard's live chat message / event log never provides (both
-- only report the *new* rank -- see the PROMOTE/DEMOTE handling below) for
-- cases the roster-snapshot scan can't cover either: e.g. a brand-new member
-- (auto-placed at the guild's lowest rank on join) promoted before the next
-- roster scan ever captured them sitting at that starting rank, so there's no
-- snapshot-to-snapshot transition to diff against.
local function FindKnownRankBefore(name, beforeTime)
    local key = MatchKey(name)
    for _, e in ipairs(GuildLogDB.entries) do
        if e.timestamp < beforeTime then
            if e.type == "JOIN" and e.rank ~= "" and MatchKey(e.actor) == key then
                return e.rank
            elseif (e.type == "PROMOTE" or e.type == "DEMOTE")
               and e.newRank ~= "" and MatchKey(e.target) == key then
                return e.newRank
            end
        end
    end
    return ""
end

-- Last-resort fallback for a rank GuildLog has no history for at all (no
-- JOIN or prior PROMOTE/DEMOTE on record -- e.g. the player joined before
-- GuildLog was installed). Blizzard always places a new member at the
-- guild's lowest configured rank, so that's the best available guess for a
-- first-ever promotion. Determined from whichever current roster member
-- sits at the highest rankIndex (lower rank = higher index in Blizzard's
-- numbering) rather than the guild-control API, since reading the roster
-- doesn't require any officer/control permissions.
local function GetLowestGuildRank()
    local maxIndex, rankName = -1, ""
    local count = GetNumGuildMembers()
    for i = 1, count do
        local _, thisRankName, rankIndex = GetGuildRosterInfo(i)
        if rankIndex and rankIndex > maxIndex then
            maxIndex, rankName = rankIndex, thisRankName or ""
        end
    end
    return rankName
end

-- Best available old rank for a promote/demote Blizzard didn't provide one
-- for: GuildLog's own history first (precise -- an actual observed rank for
-- this specific player), falling back to the guild's lowest rank (a guess,
-- but the correct one for a first-ever promotion) only when there's no
-- history to draw on at all.
local function BackfillOldRank(name, beforeTime)
    local known = FindKnownRankBefore(name, beforeTime)
    if known ~= "" then return known end
    return GetLowestGuildRank()
end

local function HandleLiveGuildEvent(_, message)
    if not GuildLogDB or not IsInGuild() then return end

    -- Patch 12.0 secret values: CHAT_MSG_SYSTEM messages delivered to tainted
    -- (addon) code during combat arrive as "secret strings" that cannot be
    -- indexed or pattern-matched (message:find errors out). Guild events are
    -- never secret, so any secret message is noise to us -- bail before indexing.
    if issecretvalue and issecretvalue(message) then return end

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
            AddEntry(EVENT_PROMOTE, officer, target, BackfillOldRank(target, now), rank, now)
        end

    elseif message:find("has demoted", 1, true) then
        local officer, target, rank = message:match(pat_demote)
        if not officer then return end
        if not IsDuplicate(EVENT_DEMOTE, officer, target, now) then
            AddEntry(EVENT_DEMOTE, officer, target, BackfillOldRank(target, now), rank, now)
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

    -- Invites are folded into their matching join rather than logged on their
    -- own: an accepted invite reads as one "Joined" line with the inviter
    -- shown as detail instead of two separate rows. Processing runs oldest to
    -- newest (see loop direction below), so an invite is always seen before
    -- its join within the same scan and can be stashed here for pairing.
    local pendingInviters = {}  -- invitee name -> officer name

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

            if ourType == EVENT_INVITE and not skip then
                pendingInviters[MatchKey(player2)] = player1
                skip = true  -- never logged on its own; folded into the join below
            end

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

                local invitedBy = ""
                if ourType == EVENT_JOIN then
                    local key = MatchKey(player1)
                    invitedBy = pendingInviters[key] or ""
                    pendingInviters[key] = nil
                end
                local target = (ourType == EVENT_JOIN) and invitedBy or player2

                local existing = FindDuplicate(ourType, player1, target, approxTime)
                if existing then
                    -- A live-detected join (target="") predates the log confirming
                    -- the inviter -- backfill it onto the same line instead of
                    -- adding a second entry.
                    if ourType == EVENT_JOIN and invitedBy ~= "" and existing.target == "" then
                        existing.target = invitedBy
                    end
                else
                    local rank, newRank
                    if ourType == EVENT_PROMOTE or ourType == EVENT_DEMOTE then
                        newRank = rankName
                        rank = BackfillOldRank(target, approxTime)
                    else
                        rank = rankName
                    end
                    AddEntry(ourType, player1, target, rank, newRank, approxTime)
                    added = added + 1
                end
            end
        end
    end

    lastScanSig = currentSig
    return added
end

-- == Roster snapshot scan =====================================================
-- Backup detection layer, in the spirit of Guild Roster Manager: periodically
-- snapshots GetGuildRosterInfo() and diffs it against the previous snapshot.
-- This catches things the chat-message/event-log paths above can miss --
-- membership or rank changes that happened while nobody with the addon was
-- online, or events that fell off Blizzard's 20-entry event log cap -- and it's
-- the only way to see public/officer note edits, since Blizzard exposes no chat
-- message or log event for those at all.
--
-- The snapshot itself is the dedup mechanism for NOTE/ONOTE: a diff only fires
-- once because the stored value is updated right after. JOIN/LEAVE/PROMOTE/
-- DEMOTE backups run through the same IsDuplicate() the live/log paths use so
-- they don't double up with an event those paths already recorded.
--
-- Declared here, ahead of ForceRescan below, so ForceRescan's reset of
-- lastRosterScanTime resolves to this local instead of silently creating an
-- unrelated global (Lua closures only capture locals already in scope at the
-- point a function is defined -- ForceRescan used to be defined earlier in
-- the file, before this declaration existed).
local ROSTER_SCAN_MIN_INTERVAL = 30  -- seconds between full roster diffs
local lastRosterScanTime = 0

-- Bump whenever the snapshot's dict-key scheme changes (see MatchKey/
-- BuildRosterSnapshot) OR nameIndex's semantics change. GuildLogDB.rosterSnapshot
-- persists across sessions, so a stored snapshot keyed under an old scheme
-- would look completely unrecognizable to a diff using the new one -- every
-- current member's new key is missing from the old snapshot and vice versa,
-- which reads as the entire guild leaving and rejoining at once.
-- GuildLogDB.nameIndex has the same problem in a subtler form: an early
-- version of ResolveDisplayName's own-realm guess was persisted as if it
-- were a confirmed sighting, so an install that ran that version can have a
-- short name on record with a bogus second "realm" alongside the real one.
-- That reads as genuine ambiguity (2+ confirmed realms), and MatchKey
-- resolves an already-suffixed input differently from a bare one under
-- ambiguity (trusts the former as-is, falls back to short for the latter) --
-- so the same player's bare and suffixed mentions stop matching each other,
-- and /glog fixup's merge pass can't recognize them as the same event.
-- DiscardStaleRosterState() (called from OnInitialize) drops both instead of
-- using them whenever this doesn't match what's saved, so the next scan
-- quietly re-establishes a clean baseline (same as a genuinely first-ever
-- snapshot -- DiffRosterSnapshot's `if not oldSnap` guard logs nothing for
-- it) instead of logging the whole roster as fresh joins, and nameIndex
-- rebuilds from only-ever-confirmed sightings going forward.
local ROSTER_SNAPSHOT_SCHEMA = 3

-- Forces a full re-scan of Blizzard's guild event log from scratch.
-- Called by the Refresh button, and implicitly after Clear Log.
-- Resets the watermark so ScanGuildLog processes all 20 events on the next
-- GUILD_EVENT_LOG_UPDATE, then requests fresh data from the server.
function GuildLog.ForceRescan()
    lastScanSig = nil
    lastRosterScanTime = 0
    C_GuildInfo.GuildRoster()
    QueryGuildEventLog()
end

-- Returns the snapshot plus how many roster slots Blizzard reports total, so
-- callers can tell a genuinely small guild apart from a big one whose member
-- details just haven't streamed in yet (see ScanRosterForChanges).
-- Keyed by MatchKey (stable across a session) rather than ResolveDisplayName's
-- result (can legitimately change mid-session) -- see MatchKey's comment.
local function BuildRosterSnapshot()
    local snapshot = {}
    local resolved = 0
    local count = GetNumGuildMembers()
    for i = 1, count do
        local name, rankName, rankIndex, level, _, _, note, officerNote = GetGuildRosterInfo(i)
        if name and name ~= "" then
            local key = MatchKey(name)
            snapshot[key] = {
                -- The roster is the strongest signal available for a name's
                -- real realm -- resolved here for storage/display even though
                -- the dict key above stays short-and-stable.
                displayName = ResolveDisplayName(name),
                rankName    = rankName  or "",
                rankIndex   = rankIndex or 0,
                level       = level     or 0,
                note        = note      or "",
                officerNote = officerNote or "",
            }
            resolved = resolved + 1
        end
    end
    return snapshot, resolved, count
end

local function DiffRosterSnapshot(oldSnap, newSnap)
    if not oldSnap then return end  -- first-ever snapshot: nothing to compare against
    local now = time()

    for key, new in pairs(newSnap) do
        local old = oldSnap[key]
        local name = new.displayName
        if not old then
            if not IsDuplicate(EVENT_JOIN, name, "", now) then
                AddEntry(EVENT_JOIN, name, "", new.rankName, "", now)
            end
        else
            if new.rankIndex ~= old.rankIndex then
                -- Lower rankIndex = higher rank in Blizzard's numbering.
                local evt = (new.rankIndex > old.rankIndex) and EVENT_DEMOTE or EVENT_PROMOTE
                -- The live chat message and Blizzard's event log both only ever
                -- report the *new* rank -- this snapshot diff is the only path
                -- that knows the old one, since it's comparing two full rosters.
                -- The live/log path almost always records its incomplete entry
                -- first (near-instant vs. this scan's 30s+ gate), so backfill the
                -- existing entry's rank instead of discarding the one place that
                -- actually has it -- otherwise every promote/demote shows "?" for
                -- the old rank permanently.
                local existing = FindDuplicate(evt, "", name, now)
                if existing then
                    if existing.rank == "" and old.rankName ~= "" then
                        existing.rank = old.rankName
                    end
                else
                    AddEntry(evt, "", name, old.rankName, new.rankName, now)
                end
            end
            if new.note ~= old.note then
                AddEntry(EVENT_NOTE, name, "", old.note, new.note, now)
            end
            if new.officerNote ~= old.officerNote then
                AddEntry(EVENT_ONOTE, name, "", old.officerNote, new.officerNote, now)
            end
        end
    end

    for key, old in pairs(oldSnap) do
        if not newSnap[key] then
            local name = old.displayName
            if not IsDuplicate(EVENT_LEAVE, name, "", now) then
                AddEntry(EVENT_LEAVE, name, "", "", "", now)
            end
        end
    end
end

-- Forces a fresh roster diff on the next GUILD_ROSTER_UPDATE by clearing the
-- interval gate. Doesn't call GuildRoster() itself -- callers that need fresh
-- server data should request it separately.
local function ScanRosterForChanges()
    if not GuildLogDB or not IsInGuild() then return end
    local newSnap, resolved, expectedCount = BuildRosterSnapshot()
    if next(newSnap) == nil then return end  -- roster not populated yet

    -- Blizzard streams member details in over several GUILD_ROSTER_UPDATE
    -- events for large guilds -- GetNumGuildMembers() is available immediately,
    -- but GetGuildRosterInfo() can still return nil names for slots that
    -- haven't loaded yet, leaving newSnap smaller than the real roster. Diffing
    -- a partial snapshot against a full previous one would log everyone still
    -- missing as having left. Wait for the next scan instead of overwriting the
    -- stored snapshot with incomplete data.
    if resolved < expectedCount then return end

    DiffRosterSnapshot(GuildLogDB.rosterSnapshot, newSnap)
    GuildLogDB.rosterSnapshot = newSnap
    lastRosterScanTime = time()
end

-- == Startup dedup cleanup ====================================================
-- 1. Drops INVITE entries with an empty target -- these are the spurious join
--    notifications WoW logs alongside the real invite; proper "join" events are
--    now captured via the EVENT_JOIN type instead.
-- 2. Removes time-based duplicates (same type/actor/target/rank/newRank within
--    3600 s) that accumulated before the 7200-second IsDuplicate window was
--    introduced. rank/newRank are part of the key -- without them, two
--    different NOTE edits to the same player within the hour (same
--    type/actor/target, different old/new text) would look identical and the
--    older one would get dropped as a false "duplicate".
-- Safe to run every load -- idempotent once the log is clean.

local function PurgeExistingDuplicates()
    local entries = GuildLogDB.entries
    local before = #entries
    if before < 2 then return end

    table.sort(entries, function(a, b) return a.timestamp > b.timestamp end)

    local kept   = {}
    local byKey  = {}  -- "type\1actor\1target\1rank\1newRank" -> list of kept timestamps
    for _, e in ipairs(entries) do
        local skip = (e.type == "LEAVE"  and (e.actor  == nil or e.actor  == ""))
                  or (e.type == "INVITE" and (e.target == nil or e.target == ""))
        if not skip then
            local key = (e.type or "") .. "\1" .. (e.actor or "") .. "\1" .. (e.target or "")
                     .. "\1" .. (e.rank or "") .. "\1" .. (e.newRank or "")
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

-- One-time-per-load migration: ScanGuildLog used to log every invite as its
-- own entry; it now folds an invite into its matching join instead (see
-- ScanGuildLog). This merges any INVITE/JOIN pairs already sitting in a
-- player's saved log from before that change, so old history reads the same
-- way new entries do. Idempotent -- once merged, there are no more INVITE
-- entries left to find, so this is a cheap no-op on every later load.
local function MergeStoredInvites()
    local entries = GuildLogDB.entries
    if #entries < 2 then return end

    -- JOIN entries with no inviter yet, grouped by joiner name.
    local openJoins = {}
    for _, e in ipairs(entries) do
        if e.type == "JOIN" and e.target == "" then
            openJoins[e.actor] = openJoins[e.actor] or {}
            table.insert(openJoins[e.actor], e)
        end
    end

    local toRemove = {}
    local merged = 0
    for idx, e in ipairs(entries) do
        if e.type == "INVITE" then
            local candidates = openJoins[e.target]
            if candidates and #candidates > 0 then
                -- Pick whichever candidate join is closest in time to this invite.
                local bestPos, bestDiff
                for pos, j in ipairs(candidates) do
                    local diff = math.abs(j.timestamp - e.timestamp)
                    if not bestDiff or diff < bestDiff then
                        bestPos, bestDiff = pos, diff
                    end
                end
                candidates[bestPos].target = e.actor
                table.remove(candidates, bestPos)
                toRemove[#toRemove + 1] = idx
                merged = merged + 1
            end
        end
    end

    if merged > 0 then
        table.sort(toRemove, function(a, b) return a > b end)
        for _, idx in ipairs(toRemove) do
            table.remove(entries, idx)
        end
        print(string.format("|cff00ccff[GuildLog]|r Merged %d invite %s into their matching Joined %s.",
            merged, merged == 1 and "entry" or "entries", merged == 1 and "entry" or "entries"))
    end
end

-- One-time-per-load migration: see ROSTER_SNAPSHOT_SCHEMA's comment. Safe to
-- run every load -- a no-op once GuildLogDB.rosterSnapshotSchema matches.
local function DiscardStaleRosterState()
    if GuildLogDB.rosterSnapshotSchema ~= ROSTER_SNAPSHOT_SCHEMA then
        GuildLogDB.rosterSnapshot = nil
        GuildLogDB.nameIndex = nil
        GuildLogDB.rosterSnapshotSchema = ROSTER_SNAPSHOT_SCHEMA
    end
end

-- == Roster-scan corruption recovery =========================================
-- Recovery for logs corrupted by the two roster-snapshot-scan bugs above: a
-- partial snapshot diffed mid-load could snowball into repeated storms of
-- JOIN/LEAVE (and PROMOTE/DEMOTE/NOTE/ONOTE) entries every ~30s while the
-- roster was still loading, and realm-suffix inconsistency could split one
-- player into two "different" people. Both are now fixed going forward (see
-- ScanRosterForChanges and ResolveDisplayName), but existing saved logs can
-- still be carrying thousands of bogus entries from before the fix.
--
-- Not run automatically -- the burst threshold below is a judgment call about
-- data that's already corrupted, not something to apply silently. Opt in via
-- "/glog fixup".
--
-- BURST_THRESHOLD: entries sharing the same timestamp+type are treated as a
-- corrupted-scan burst once there are this many. A real guild essentially
-- never has 15+ genuine joins/leaves/promotes/note-changes land in the same
-- second; that pattern is the signature of a partial snapshot getting diffed
-- against a full one. Chosen from an actual corrupted log where genuine
-- clusters (deliberate multi-kick, etc.) topped out at 12 while corrupted
-- bursts started at 19 and ran into the hundreds -- comfortably clear of the
-- legitimate range on both sides.
local BURST_THRESHOLD = 15

-- Types whose live/log/roster-scan paths can each record the same real-world
-- event with different actor/target completeness (see IsDuplicate's callers).
-- NOTE/ONOTE are deliberately excluded: those don't go through IsDuplicate
-- when first recorded, so two different edits to the same player can
-- legitimately share an empty target within the window and must not merge.
local MERGEABLE_TYPES = {
    JOIN = true, LEAVE = true, REMOVE = true, PROMOTE = true, DEMOTE = true,
}

-- Collapses leftover pairs like the Tt / Tt-Detheroc case: the same event
-- recorded twice under what used to be two different-looking names, one copy
-- knowing more (actor, old rank) than the other. Mirrors FindDuplicate's
-- wildcard actor/target matching, but sweeps the whole log instead of
-- checking one new entry against history, and backfills whichever fields the
-- surviving entry is missing before dropping the redundant copy.
local function MergePhantomDuplicates()
    local entries = GuildLogDB.entries
    if #entries < 2 then return 0 end

    table.sort(entries, function(a, b) return a.timestamp > b.timestamp end)

    local removed = 0
    local i = 1
    while i <= #entries do
        local e = entries[i]
        local dupIdx = nil
        if MERGEABLE_TYPES[e.type] then
            -- Compare by MatchKey, not the stored value directly: two entries
            -- for the same player can hold different resolved forms if their
            -- realm resolution changed between when each was written (see
            -- MatchKey's comment).
            local eActorKey  = e.actor  ~= "" and MatchKey(e.actor)  or ""
            local eTargetKey = e.target ~= "" and MatchKey(e.target) or ""
            for j = i + 1, #entries do
                local o = entries[j]
                if e.timestamp - o.timestamp > DEDUP_WINDOW then break end
                local oActorKey  = o.actor  ~= "" and MatchKey(o.actor)  or ""
                local oTargetKey = o.target ~= "" and MatchKey(o.target) or ""
                if o.type == e.type
                   and (oActorKey  == eActorKey  or oActorKey  == "" or eActorKey  == "")
                   and (oTargetKey == eTargetKey or oTargetKey == "" or eTargetKey == "") then
                    dupIdx = j
                    break
                end
            end
        end
        if dupIdx then
            local kept = entries[dupIdx]
            if kept.actor   == "" and e.actor   ~= "" then kept.actor   = e.actor   end
            if kept.target  == "" and e.target  ~= "" then kept.target  = e.target  end
            if kept.rank    == "" and e.rank    ~= "" then kept.rank    = e.rank    end
            if kept.newRank == "" and e.newRank ~= "" then kept.newRank = e.newRank end
            table.remove(entries, i)
            removed = removed + 1
            -- Don't advance i -- the next entry has shifted into this slot.
        else
            i = i + 1
        end
    end
    return removed
end

local function FixCorruptedRosterScanEntries()
    local entries = GuildLogDB.entries
    if #entries == 0 then
        print("|cff00ccff[GuildLog]|r No entries to clean up.")
        return
    end

    -- Seed the ambiguity index from the live roster first -- it's the
    -- strongest signal for who's genuinely ambiguous (2+ realms sharing a
    -- short name) before resolving any stored name against it.
    BuildRosterSnapshot()

    -- Re-resolve every stored name against that index -- entries logged
    -- before the realm-suffix fix may still hold a bare or inconsistent form.
    for _, e in ipairs(entries) do
        e.actor  = ResolveDisplayName(e.actor)  or ""
        e.target = ResolveDisplayName(e.target) or ""
    end

    local counts = {}
    for _, e in ipairs(entries) do
        local key = e.timestamp .. "\1" .. e.type
        counts[key] = (counts[key] or 0) + 1
    end

    local kept = {}
    local burstRemoved = 0
    for _, e in ipairs(entries) do
        local key = e.timestamp .. "\1" .. e.type
        if counts[key] >= BURST_THRESHOLD then
            burstRemoved = burstRemoved + 1
        else
            kept[#kept + 1] = e
        end
    end
    GuildLogDB.entries = kept

    local phantomsMerged = MergePhantomDuplicates()

    print(string.format(
        "|cff00ccff[GuildLog]|r Fixup: normalized names, removed %d corrupted burst %s, merged %d phantom duplicate %s (%d remaining).",
        burstRemoved, burstRemoved == 1 and "entry" or "entries",
        phantomsMerged, phantomsMerged == 1 and "entry" or "entries",
        #GuildLogDB.entries))

    PurgeExistingDuplicates()
    MergeStoredInvites()
end

-- == AceAddon lifecycle =======================================================

function GuildLog:OnInitialize()
    GuildLogDB = GuildLogDB or {}
    GuildLogDB.entries = GuildLogDB.entries or {}
    PurgeExistingDuplicates()
    MergeStoredInvites()
    DiscardStaleRosterState()

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
        elseif msg == "fixup" then
            FixCorruptedRosterScanEntries()
        elseif msg == "scan" then
            local before = #GuildLogDB.entries
            print("|cff00ccff[GuildLog]|r Scanning...")
            GuildLog.ForceRescan()
            -- Both the event-log scan (0.5s debounce) and the roster-diff scan
            -- (1s debounce) run async off the GUILD_EVENT_LOG_UPDATE/
            -- GUILD_ROSTER_UPDATE events ForceRescan triggers; comparing the
            -- entry count before/after a window wide enough for both to land is
            -- simpler than threading a combined count through two independent
            -- completion callbacks.
            C_Timer.After(2, function()
                local added = #GuildLogDB.entries - before
                if added > 0 then
                    print(string.format(
                        "|cff00ccff[GuildLog]|r Manual scan complete -- %d new %s found.",
                        added, added == 1 and "entry" or "entries"))
                else
                    print("|cff00ccff[GuildLog]|r Manual scan complete -- no new entries found.")
                end
            end)
        elseif msg == "stats" then
            UpdateAddOnMemoryUsage()
            local memKB = GetAddOnMemoryUsage("GuildLog")
            local line = string.format("|cff00ccff[GuildLog]|r Memory: %.1f KB", memKB)
            -- CPU tracking only accumulates while Lua script profiling is on; it's
            -- off by default because profiling itself costs performance, so it's
            -- opt-in rather than something GuildLog enables on your behalf.
            if GetCVar("scriptProfile") == "1" then
                UpdateAddOnCPUUsage()
                local cpuMS = GetAddOnCPUUsage("GuildLog")
                line = line .. string.format(" | CPU: %.2f ms (cumulative since profiling started)", cpuMS)
            else
                line = line .. " | CPU: run '/console scriptProfile 1' then /reload to enable CPU tracking"
            end
            print(line)
        else
            GuildLogUI_Open()
        end
    end

    print("|cff00ccff[GuildLog]|r Loaded. Type |cffffff00/glog|r to open, |cffffff00/glog scan|r to check for changes now, |cffffff00/glog fixup|r to clean up entries from the roster-scan bug, |cffffff00/glog stats|r for memory/CPU usage.")
end

function GuildLog:OnEnable()
    BuildLivePatterns()
    self:RegisterEvent("CHAT_MSG_SYSTEM", HandleLiveGuildEvent)

    -- Debounce GUILD_EVENT_LOG_UPDATE: WoW fires it multiple times in rapid succession
    -- on login. Collapsing the burst ensures a single consistent `now` for the scan.
    -- Runs silently -- routine scans (startup or periodic) aren't announced to
    -- chat; /glog scan exists for on-demand, explicit feedback instead.
    local scanTimer = nil
    local function DebouncedScan()
        if scanTimer then scanTimer:Cancel() end
        scanTimer = C_Timer.NewTimer(0.5, function()
            scanTimer = nil
            ScanGuildLog()
        end)
    end
    self:RegisterEvent("GUILD_EVENT_LOG_UPDATE", DebouncedScan)
    self:RegisterEvent("PLAYER_GUILD_UPDATE", function()
        C_GuildInfo.GuildRoster()
    end)

    -- Debounced roster snapshot scan: catches note/rank/membership changes with
    -- no chat message or Blizzard event-log entry. GUILD_ROSTER_UPDATE fires very
    -- often (e.g. any guildmate going on/offline), so a short debounce plus the
    -- ROSTER_SCAN_MIN_INTERVAL gate inside ScanRosterForChanges keep this from
    -- doing a full roster diff constantly in a large, active guild.
    local rosterScanTimer = nil
    local function DebouncedRosterScan()
        if rosterScanTimer then rosterScanTimer:Cancel() end
        rosterScanTimer = C_Timer.NewTimer(1, function()
            rosterScanTimer = nil
            if time() - lastRosterScanTime >= ROSTER_SCAN_MIN_INTERVAL then
                ScanRosterForChanges()
            end
        end)
    end
    self:RegisterEvent("GUILD_ROSTER_UPDATE", DebouncedRosterScan)

    -- Actively request fresh roster data on a timer rather than relying solely
    -- on Blizzard to push GUILD_ROSTER_UPDATE on its own -- note edits don't
    -- reliably trigger it, so without this poll a note change made by an
    -- officer could go undetected for the rest of the session.
    C_Timer.NewTicker(ROSTER_SCAN_MIN_INTERVAL, function()
        if IsInGuild() then
            C_GuildInfo.GuildRoster()
        end
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
