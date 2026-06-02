# Changelog

All notable changes to GuildLog will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semver](https://semver.org/).
Update on every PR. Add your name to the version header line.

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
