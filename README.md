# GuildLog

[![Version](https://img.shields.io/badge/version-0.0.1-blue)](CHANGELOG.md)
[![WoW Interface](https://img.shields.io/badge/WoW-12.0.5_%7C_120005-orange)](https://warcraft.wiki.gg/wiki/Patch_12.0.5)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Lint](https://github.com/YOUR_USERNAME/GuildLog/actions/workflows/lint.yml/badge.svg)](https://github.com/YOUR_USERNAME/GuildLog/actions/workflows/lint.yml)

> Replace `YOUR_USERNAME` in the Lint badge URL above once the repo is created.

A lightweight World of Warcraft addon that captures and displays guild events with **real timestamps** (not "3 days ago") and **full actor names**.

## Features

- Logs all guild events: invites, kicks, leaves, promotions, demotions
- Real `YYYY-MM-DD HH:MM:SS` timestamps stored in SavedVariables — survive reloads and restarts
- Events that occurred while offline are stamped with their **actual time**, not the login time
- Shows **who** did the action (e.g. "OfficerName invited NewPlayer")
- Filter by event type (Invites / Removals / Leaves / Promotions / Demotions)
- Search by player name
- Unlimited history by default (configurable via `GuildLog.MAX_ENTRIES`)
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

- Blizzard's `GetGuildEventInfo()` only returns the **last 20 guild events** from the server. GuildLog captures each event as it arrives and persists them in `SavedVariables`, so over time your log grows well beyond that limit and survives restarts.
- Events that occurred while you were offline are stamped with their **actual event time** (derived from Blizzard's relative offset), not the time you logged in.
- On each login, GuildLog deduplicates the replayed 20 events against what is already stored, so no double entries accumulate over time.
- If you were offline when events occurred, you'll only recover up to the 20 most recent ones on next login (Blizzard server limitation — older history is not sent).
- History is **unlimited by default**. The `SavedVariables` file will grow over time. To cap it, set `GuildLog.MAX_ENTRIES` to a positive number in-game via `/run GuildLog.MAX_ENTRIES = 2000`.
- The addon **does not modify any guild ranks or members** — it is purely read-only.

## Interface version

Currently set to `120005` (Midnight 12.0.5). Update the `## Interface:` line in `GuildLog.toc` to match your client version if needed.
