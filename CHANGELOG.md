# Changelog

All notable changes to GuildLog will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semver](https://semver.org/).
Update on every PR. Add your name to the version header line.

---

## [0.6.2] — 2026-08-16 — Katorri

### Fixed
- Realm-suffix resolution could still produce duplicate/split identities
  despite 0.6.1's fix. The root cause was subtler: `ResolveDisplayName()`'s
  result for a given short name can legitimately change mid-session (a
  guessed own-realm placeholder gets upgraded to a confirmed realm the first
  time a trusted source hands back the suffixed form), but that resolved
  value was still being used directly for matching/comparison in several
  places -- the roster-snapshot diff's dict key, `FindDuplicate`,
  `FindMemberRank`, the invite/join pairing in `ScanGuildLog`, and the
  duplicate-merge pass in `/glog fixup`. Any of those comparisons could see
  the *same* player as two different people the moment their resolution
  changed -- e.g. Blizzard's event log gets rescanned from scratch on every
  login, so an entry logged under a guessed identity last session could fail
  to match this session's now-confirmed identity and get relogged as new.
  All of those now compare through a new `MatchKey()` -- the short name,
  unless it's genuinely ambiguous (2+ confirmed realms on record for it) --
  which stays stable regardless of how the display resolution evolves.
  `ResolveDisplayName()`'s own-realm guess also no longer gets persisted as
  a confirmed sighting, since a wrong guess colliding with the real realm
  later would have created false ambiguity.
- Promotions/demotions could still show "?" for the old rank in cases the
  0.6.1 backfill didn't cover: a brand-new member (auto-placed at the
  guild's lowest rank on join) promoted before the next roster scan ever
  captured them sitting at that starting rank has no snapshot-to-snapshot
  transition to diff, so there was nothing to backfill from. The old rank is
  now looked up from the player's own history first (their starting rank
  from JOIN, or their rank after their most recent PROMOTE/DEMOTE) and,
  failing that, falls back to the guild's actual lowest configured rank --
  Blizzard always places new members there, so it's the correct guess for a
  first-ever promotion with no other history to draw on.
- Deploying the `MatchKey()` fix above one-time-corrupted every existing
  installation's log: `GuildLogDB.rosterSnapshot` persists across sessions,
  and a snapshot saved under the old dict-key scheme reads as completely
  unrecognizable to a diff using the new one, which looks exactly like the
  entire guild leaving and rejoining at once. A schema version now gates the
  stored snapshot; a mismatch discards it instead of diffing against it, so
  the next scan quietly re-establishes a baseline (same as a genuinely
  first-ever snapshot) instead of logging the whole roster as fresh joins.
- An earlier version of `ResolveDisplayName()`'s own-realm guess (before it
  was fixed to stop doing this) could get persisted into `nameIndex` as if
  it were a confirmed sighting, leaving some installs with a bogus second
  "realm" on record for a short name alongside the real one. That reads as
  genuine ambiguity, and `MatchKey()` resolves an already-suffixed input
  differently from a bare one under ambiguity (trusts the former as-is,
  falls back to short for the latter) -- so a player's bare and suffixed
  mentions stopped matching each other, and `/glog fixup`'s merge pass
  couldn't recognize them as the same event even after the fixes above.
  The same schema version now also discards `nameIndex` when it changes, so
  it rebuilds from only-ever-confirmed sightings.
- `BuildRosterSnapshot()` computed each member's snapshot key with `MatchKey`
  while, in the same pass, populating the very index `MatchKey` reads to
  decide ambiguity (via `ResolveDisplayName`'s side effect for the display
  name). In a guild with two different members sharing a short name (common
  in a large cross-realm community guild), whichever one was processed first
  in the roster didn't see the other's realm registered yet and got keyed by
  the bare short name; the second one, now seeing the first's realm on
  record, got keyed by its full name -- so they didn't collide within one
  scan, but *which* of the two held the short key flipped depending on
  roster order, producing a spurious leave+join pair for one of them on
  every subsequent scan. Split into two passes: every member's realm is
  recorded first, and keys are only computed once the index is fully
  settled for that scan, so the result no longer depends on iteration
  order. The schema version was bumped again, since a snapshot built by the
  single-pass version may already have one member's data silently
  overwritten by the other's under a shared short key.
  `/glog fixup` alone couldn't fix this one -- it cleans up symptoms
  (bursts, mergeable duplicates), but the generator was still producing
  fresh churn every scan; run it again after this update lands to clean up
  what already accumulated.
- Resetting `nameIndex` (see the two entries above) wasn't enough on its own
  for a short name whose fabricated realm guess had already been written
  directly into a stored entry's `actor`/`target` field, rather than just
  living in the index -- the very next `/glog fixup` run would trust that
  already-suffixed value at face value and re-confirm the bad guess right
  back into the freshly-reset index. `/glog fixup` now also purges that one
  specific pattern (a short name on record with both a real realm and one
  that exactly matches "your own realm," which is the only formula the
  fabricated guess could have used), rewriting any stored entry still
  holding the fabricated value.
- The snapshot-key churn from the `BuildRosterSnapshot` ordering bug above
  logged a real member as leaving and immediately rejoining, and neither
  existing cleanup pass could catch it: the burst-removal counts entries
  sharing one timestamp *per type*, so a churn event split across JOIN and
  LEAVE could land under the threshold on each type individually even
  though the mix as a whole was obviously not real membership change; and
  the phantom-duplicate merge only merges two entries of the *same* type
  describing one event, not two different types. `/glog fixup` now also
  cancels a JOIN and a LEAVE for the same player within a 10-minute window
  as a pair, on top of the existing cleanup passes.

## [0.6.1] — 2026-08-16 — Katorri

### Changed
- The startup/periodic scans no longer announce themselves in chat every
  single login ("Startup scan complete -- N new events / no new events"),
  matching how Guild Roster Manager treats routine scans as silent
  background work rather than something worth a chat line every time.

### Fixed
- Roster snapshot scan could log every guild member as having left at once.
  For large guilds, Blizzard streams member details in over several
  `GUILD_ROSTER_UPDATE` events rather than delivering them all at once;
  `GetNumGuildMembers()` reports the final count immediately, but
  `GetGuildRosterInfo()` can still return a nil name for slots that haven't
  loaded yet. The snapshot scan would silently skip those unresolved slots,
  diff the resulting partial roster against the last full snapshot, and log
  every member missing from the partial snapshot as a LEAVE. The scan now
  waits until every roster slot has resolved a name before diffing.
- The same player could be logged as two different people. Blizzard only
  appends a "-Realm" suffix to a name when needed to disambiguate, and
  `GetGuildRosterInfo()`, `GetGuildEventInfo()`, and `CHAT_MSG_SYSTEM` text
  didn't always agree on whether a given moment counted as ambiguous. Since
  names were used as-is for roster-snapshot keys and duplicate-detection
  matching, that disagreement made the same player look like two different
  people -- producing a spurious extra "Joined"/"Promoted" row with no prior
  record to read the old rank from (shown as "?"). Every name is now resolved
  through a realm index before it's stored, matched, or displayed: a
  realm-qualified name is always trusted and remembered, a bare name is
  upgraded to the one realm-qualified form on record for it, and a short name
  genuinely shared by two different guildmates across realms (e.g. the same
  name on two different connected realms) is left alone rather than guessed
  at -- so two real players are never silently merged into one, and the
  realm is still shown wherever it's known.
- Promotions/demotions almost always showed "?" for the old rank instead of
  the real one. The live chat message and Blizzard's event log both only
  ever report the *new* rank -- the roster-snapshot scan is the only path
  that knows the old one, since it's comparing two full rosters. Because the
  live/log path detects a promotion almost instantly while the snapshot scan
  is gated to run at most every 30s, the incomplete entry (old rank unknown)
  nearly always landed first; when the snapshot scan later found the same
  promotion with the real old rank, it was silently discarded as an already-
  seen duplicate instead of backfilling it in. The snapshot diff now
  backfills the existing entry's old rank instead of discarding the one
  place that actually has it.

### Added
- `/glog fixup` -- a one-time recovery command for logs already corrupted by
  the two bugs above. The partial-snapshot bug could snowball: a partial
  roster diffed against a full snapshot logs a burst of bogus LEAVEs, that
  partial snapshot then gets saved as the new baseline, and the next scan
  (still mid-load) diffs against *that*, producing another bogus burst -- on
  an affected account this inflated a log that should hold a few thousand
  entries to over 19,000. `/glog fixup` re-resolves every stored name against
  the realm index, strips out bursts of 15+ same-type entries sharing one
  timestamp (the signature of a corrupted scan -- real guilds don't have that
  many genuine joins/leaves/promotes/note-changes land in the same second),
  and merges leftover duplicate pairs left by the realm-suffix bug,
  backfilling whichever fields each copy is missing. Opt-in only, since the
  burst threshold is a judgment call about already-corrupted data rather than
  something to apply silently.
- `/glog scan` -- forces an immediate rescan (event log + roster) and reports
  back explicitly ("Scanning..." then "Manual scan complete -- N new entries
  found"), for on-demand confirmation that scanning is actually working
  without needing ambient chat spam to infer it.

## [0.6.0] — 2026-08-16 — Katorri

### Added
- The log window can now be resized by dragging its bottom-right corner grip,
  and the Time/Event/Player columns can be individually resized by dragging
  the dividers between their headers (the Details column always absorbs
  whatever space is left). Both window size and column widths persist across
  sessions. The row list grows or shrinks to fit however tall the window is,
  up to 60 visible rows.

## [0.5.0] — 2026-08-06 — Katorri

### Changed
- Added 120100 to the TOC interface line for patch 12.1.0 compatibility,
  alongside the existing 120007 (12.0.7).

### Fixed
- Startup duplicate cleanup could silently delete a legitimate NOTE/ONOTE
  entry: its dedup key was `type/actor/target` only, and every note change
  for the same player shares that key regardless of old/new text, so two
  different edits to the same player within an hour looked like duplicates
  and the older one got dropped. The key now also includes `rank`/`newRank`
  (the old/new values) so only truly identical entries are treated as dupes.

### Added
- Roster snapshot scan, similar in spirit to Guild Roster Manager: periodically
  diffs the full guild roster against the previous snapshot to catch changes
  the chat-message/event-log paths can miss -- membership or rank changes that
  happened while nobody with the addon was online, or events that fell off
  Blizzard's 20-entry event log cap.
- Public and officer note change tracking (`Note changed`, `Officer note
  changed` log entries) -- Blizzard exposes no chat message or log event for
  note edits, so this is the only way GuildLog can see them.
- "Notes" filter button in the log window for the two new entry types.
- `/glog stats` -- prints GuildLog's current memory usage, and CPU time if
  Lua script profiling (`/console scriptProfile 1`) is enabled, for checking
  the addon isn't a performance drag.

### Changed
- Reworked the log window layout: rows now render in aligned Time / Event /
  Player / Details columns instead of one concatenated string, each row gets
  a left-edge accent bar colored by event type, and the list sits in a
  bordered panel with a header row for readability. Filter buttons are now
  colored toggle chips (tinted by event type, dim when off) instead of the
  stock red action-button skin, so active filters are easier to read at a
  glance.
- Entries that carry extra detail (rank changes, note edits) now span two
  lines -- e.g. a promotion shows "OldRank -> NewRank" on the first line and
  "by <officer>" dimmed underneath -- instead of cramming everything onto one
  row, similar to how Guild Roster Manager's log reads.
- Replaced the AceGUI-3.0 window frame with a hand-built one (custom title
  bar, close button, and drag/position handling) so the whole window shares
  one dark/gold theme instead of mixing AceGUI's default chrome with the
  custom panels inside it. Dropped the now-unused AceGUI-3.0 and
  AceGUIContainer-Frame libraries from the TOC and `Libs/`.
- The roster snapshot scan (see above) now also runs on an active 30-second
  timer that requests fresh roster data, instead of only reacting to
  `GUILD_ROSTER_UPDATE` firing on its own -- note edits don't reliably
  trigger that event, so without this a note change could sit undetected
  for the rest of the session.
- Invites are no longer logged as their own row. An accepted invite now reads
  as a single "Joined" line with "Invited by <officer>" as its detail,
  instead of a separate "Invited" entry plus a "Joined" entry for the same
  event. The "Invites" filter chip was renamed to "Joins" to match.
- One-time migration on load merges any INVITE/JOIN pairs already sitting in
  your saved log from before this change, so existing history reads the same
  way new entries do. Runs automatically once; harmless no-op afterward.
- Row text bumped from small to normal-size fonts across the log window for
  readability, with the window and columns widened to fit. Timestamps now
  read as `MM/DD/YY hh:mm:ss AM/PM` instead of `YYYY-MM-DD HH:MM:SS`, and the
  Time column was widened so the new format doesn't clip. Seconds were
  dropped from the display (`MM/DD/YY hh:mm AM/PM`) as unnecessary precision
  for a guild log.

### Added
- `/glog stats` -- prints GuildLog's current memory usage, and CPU time if
  Lua script profiling (`/console scriptProfile 1`) is enabled, for checking
  the addon isn't a performance drag.

---

## [0.4.2] — 2026-06-16 — Katorri

### Changed
- Bumped TOC interface version to 120007 for patch 12.0.7 compatibility.

---

## [0.4.1] — 2026-06-02 — Katorri

### Fixed
- Lua error during combat (Mythic+, raids): the live `CHAT_MSG_SYSTEM`
  handler tried to index `message` while it was a patch 12.0 "secret string"
  value, which combat-related system messages now are when delivered to addon
  code. The handler now bails out via `issecretvalue` before any pattern
  matching. Guild events are never secret, so no real events are missed.

---

## [0.4.0] — 2026-06-01 — Katorri

### Added
- Real-time guild event detection via `CHAT_MSG_SYSTEM`. Join, leave, kick,
  promotion, and demotion events are now recorded the moment they happen
  without opening the Blizzard guild log or `/reload`. Detection uses plain
  substring guards (same approach as GRM) so unrelated system messages --
  spell learns, online/offline notifications, etc. -- are never matched.
  Name extraction uses WoW global strings (`ERR_GUILD_JOIN_S`,
  `ERR_GUILD_REMOVE_SS`, `ERR_GUILD_PROMOTE_SSS`, `ERR_GUILD_DEMOTE_SSS`)
  with `[%S]+` captures for player names and `(.+)` for rank text.
- JOIN events captured live include the new member's starting rank, looked up
  from the roster 1 second after the system message fires to allow the API
  to update.
- `QueryGuildEventLog()` is called on login (2 s delay) so the startup
  Blizzard scan runs automatically without requiring the native guild log to
  be opened. It is also called alongside `GuildRoster()` whenever a live
  join, leave, or kick is detected, keeping Blizzard's buffer in sync.
- Login summary message: after the startup scan completes, a chat message
  reports how many new events were found since the last session.
- `GuildLog.ForceRescan()` resets the scan watermark and re-requests
  Blizzard's event log. Called by the Refresh button and automatically after
  Clear Log so the last 20 events repopulate immediately.

### Fixed
- Refresh button now re-fetches data from Blizzard's event log instead of
  only re-filtering the in-memory list.
- Clear Log now triggers a rescan so the log repopulates from Blizzard's
  buffer without needing a manual Refresh click.

---

## [0.3.4] — 2026-05-24 — Katorri

### Fixed
- ESC stops working after closing GuildLog when opened via the guild pane "View Log" button. Root cause: the hook hid `CommunitiesGuildLogFrame` (the child) directly, which corrupted CommunitiesFrame's internal state machine, leaving CommunitiesFrame open in a state where ESC was consumed each press but the frame never closed. The hook now calls `HideUIPanel(CommunitiesFrame)` on the parent instead, which closes the Communities panel cleanly.

---

## [0.3.3] — 2026-05-24 — Katorri

### Added
- "Blizzard Log" button at the bottom of the window opens the default Blizzard guild event log without closing GuildLog. The existing "View Log" redirect is bypassed for this one open so both windows can be compared.
- Guild joins are now recorded as a distinct `JOIN` event type. WoW fires a `"join"` event (separate from `"invite"`) when a player accepts an invite and enters the guild; these were previously dropped. Shown in a lighter green, controlled by the Invites filter button alongside invite events.

### Fixed
- `(unknown)` entries appearing alongside each invite: WoW logs a second `"invite"` event with `player2=nil` when the invitee accepts. These are now skipped in favor of the proper `"join"` event. The startup cleanup pass also removes any such entries already stored.

- Startup cleanup pass removes duplicate entries that accumulated before this fix. Groups by (type, actor, target) and drops any entry within 3600 seconds of an already-kept entry. Prints a count of removed entries and is idempotent once the log is clean.
- Duplicate entries accumulated across sessions. Root cause: Blizzard's hour offset is a truncated integer, so scanning the same event at two login times that straddle an hour boundary produces `approxTime` values that differ by exactly 3600 seconds -- well outside the previous 60-second dedup window. The mathematically correct upper bound on this drift is 7199 seconds, so `IsDuplicate` now uses a 7200-second window. `GUILD_EVENT_LOG_UPDATE` is also debounced (0.5 s) so rapid login-replay fires collapse into one scan with a single consistent timestamp.
- Unknown actor names (WoW returns nil for deleted characters in the guild event log) now display as `(unknown)` instead of `?` for clarity.
- Duplicate entries still accumulating after the dedup window fix: `GUILD_EVENT_LOG_UPDATE` fires multiple times per session (login replay plus once per live event), and each firing rescanned all 20 Blizzard events. Added a per-session signature watermark (type+player fields of Blizzard's i=1 event); a scan whose i=1 matches the previous scan's is skipped entirely, and a scan where i=1 changed processes only the new events above the old watermark. `IsDuplicate` is kept as a cross-session safety net.
- "View Log" in the Communities frame required two clicks: clicking it triggers on-demand loading of `Blizzard_Communities`, so the `OnShow` hook was not yet registered when the frame first appeared. The `ContinueOnAddOnLoaded` callback now immediately redirects if the frame is already visible when the callback fires.
- `(unknown) left the guild` entries: LEAVE events where `GetGuildEventInfo` returns nil for `player1` are now skipped on scan (same pattern as the existing nil-target INVITE filter). The startup cleanup pass now also removes any already-stored nameless LEAVE entries.
- Spam-clicking "View Log" caused CommunitiesFrame to close: each click hid `CommunitiesGuildLogFrame` directly, which broke CommunitiesFrame's internal state machine; a second `Hide()` caused it to close itself. The redirect now checks `GuildLogUI_IsOpen()` and skips entirely if GuildLog is already visible, so `CommunitiesGuildLogFrame:Hide()` is only ever called once per GuildLog session.

---

## [0.3.2] — 2026-05-22 — Katorri

### Fixed
- Voluntary guild leaves were never recorded — `GetGuildEventInfo` returns `"quit"` for leaves and `"remove"` for kicks, but the event map used `"leave"` and `"kick"` respectively, so both event types were silently dropped. Corrected both keys.
- Leave rows displayed `?` instead of the player name — the UI read `entry.target` for leave events but the departing player is stored in `entry.actor` (`player1` from `GetGuildEventInfo`). Fixed to read `actor`.

---

## [0.3.1] — 2026-05-21 — Katorri

### Fixed
- Quoted `on:` key in both workflow files to prevent YAML 1.1 boolean coercion (`on` -> `true`) from failing strict validators.
- Updated `actions/checkout` from non-existent v6 to v4 in both workflows.

---

## [0.3.0] — 2026-05-21 — Katorri

### Added
- Window position is now persisted across sessions via AceGUI's `SetStatusTable`; the log reopens where you left it instead of resetting to screen centre.

### Changed
- UI rebuilt on AceGUI-3.0 `Frame` widget, replacing the custom `BasicFrameTemplateWithInset` window. Entry count moved to the AceGUI status bar. AceGUI-3.0 embedded in `Libs\AceGUI-3.0\`.

---

## [0.2.2] — 2026-05-21 — Katorri

### Fixed
- Log entries overlapped the Clear Log / Refresh buttons at the bottom of the window — reduced visible row count from 20 to 18 and raised the list background to stop above the button bar.

---

## [0.2.1] — 2026-05-21 — Katorri

### Fixed
- Promote/demote rows displayed □ block characters instead of an arrow between the target name and new rank — WoW's built-in font doesn't include U+2192 (→); replaced with ASCII `->`.

---

## [0.2.0] — 2026-05-21 — Katorri

### Added
- "View Log" in the guild pane now opens GuildLog instead of Blizzard's 20-event native log (`CommunitiesGuildLogFrame` hook via `Blizzard_Communities`)

### Fixed
- Scrollbar crash on open — `UIPanelScrollBarTemplate` in Midnight calls into `SecureScrollTemplates` which requires a scroll-frame parent; replaced with a plain `Slider` widget

---

## [0.1.0] — 2026-05-21 — Katorri

### Fixed
- Timestamps now correctly derive the real event date from Blizzard's guild log
  (`GetGuildEventInfo` returns relative offsets — years/months/days/hours ago —
  which are now subtracted from today's date via calendar arithmetic instead of
  being misread as absolute values, which caused all entries to show today's date
  or garbage 1999 dates).

### Changed
- Log now displays newest entries at the top (sorted by timestamp descending).

---

## [0.0.1] — 2026-05-21 — Katorri

### Added
- Initial release
- Captures guild events: invites, kicks, voluntary leaves, promotions, demotions
- Persistent history via `SavedVariables` (`GuildLogDB`) — survives restarts and accumulates over time (unlimited by default)
- Real `YYYY-MM-DD HH:MM:SS` timestamps; offline events are stamped with their actual event time, not the login time
- Deduplication on login — Blizzard replays the last 20 events every session; GuildLog filters out anything already stored
- Scrollable UI window with per-type filter buttons (Invites / Removals / Leaves / Promotions / Demotions)
- Player name search
- Alternating row backgrounds for readability
- Clear Log button with confirmation dialog
- Slash commands: `/glog`, `/guildlog`, `/glog clear`, `/glog debug`
- Window closes on Escape (registered as a special frame)
- Compatible with WoW Midnight 12.0.5 (interface `120005`)
