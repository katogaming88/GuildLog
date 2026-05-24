# Changelog

All notable changes to GuildLog will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semver](https://semver.org/).
Update on every PR. Add your name to the version header line.

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
