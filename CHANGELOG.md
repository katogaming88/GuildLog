# Changelog

All notable changes to GuildLog will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semver](https://semver.org/).
Update on every PR. Add your name to the version header line.

---

## [0.3.0] — 2026-05-21 — Katorri

### Added
- Window position is now persisted across sessions; the log reopens where you left it instead of resetting to screen centre.

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
