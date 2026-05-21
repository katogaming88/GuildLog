# GuildLog

A lightweight World of Warcraft addon that captures and displays guild events with **real timestamps** (not "3 days ago") and **full actor names**.

## Features

- Logs all guild events: invites, kicks, leaves, promotions, demotions
- Real `YYYY-MM-DD HH:MM:SS` timestamps stored in SavedVariables — survive reloads and restarts
- Shows **who** did the action (e.g. "OfficerName invited NewPlayer")
- Filter by event type (Invites / Removals / Leaves / Promotions / Demotions)
- Search by player name
- Stores up to 500 entries (configurable via `GuildLog.MAX_ENTRIES`)
- Zero rank management — purely a log viewer

## Installation

1. Copy the `GuildLog/` folder into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/GuildLog/
   ```
2. Restart WoW or reload the UI (`/reload`)

## Usage

| Command | Action |
|---|---|
| `/glog` | Open the log window |
| `/guildlog` | Same as above |
| `/glog clear` | Clear all stored entries |
| `/glog debug` | Print entry count to chat |

The window also appears in the Escape menu (registered as a special frame).

## Row colors

| Color | Meaning |
|---|---|
| 🟢 Green | Invite |
| 🔴 Red | Kicked/Removed |
| 🟠 Orange | Left voluntarily |
| 🔵 Sky blue | Promoted |
| 🟣 Purple | Demoted |

## Notes

- Blizzard's `GetGuildEventInfo()` only returns the **last 20 guild events** from the server. GuildLog captures each event as it arrives and persists them, so over time your log grows beyond that limit.
- If you were offline when events occurred, you'll only see up to the 20 most recent ones on next login (Blizzard limitation — the server doesn't send older history).
- The addon **does not modify any guild ranks or members** — it is purely read-only.

## Interface version

Currently set to `120005` (Midnight 12.0.5). Update the `## Interface:` line in `GuildLog.toc` to match your client version if needed.
