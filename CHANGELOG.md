# Changelog

All notable changes to GuildLog will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [0.0.1] — 2026-05-21

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
