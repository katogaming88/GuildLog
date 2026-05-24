# Changelog

All notable changes to GuildLog will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semver](https://semver.org/).
Update on every PR. Add your name to the version header line.

---

## [0.3.3] — 2026-05-24 — Katorri

### Added
- "Blizzard Log" button at the bottom of the window opens the default Blizzard guild event log without closing GuildLog. The existing "View Log" redirect is bypassed for this one open so both windows can be compared.

### Fixed
- Duplicate entries accumulated across sessions when the sync channel prepended many entries to the log, pushing older Blizzard-log events past the previous 60-entry dedup search window. `IsDuplicate` now walks the full entry list with a time-based early exit so entries can never fall outside its reach.
- Unknown actor names (WoW returns nil for deleted characters in the guild event log) now display as `(unknown)` instead of `?` for clarity.

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
