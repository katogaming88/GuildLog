# Roadmap

Planned and considered improvements, roughly in priority order. Nothing here is committed — open an issue to discuss before building something large.

---

## Near-term

### Rank-colored actor names
- Color the actor's name in each log row by their guild rank, making it easy to see at a glance which rank sent an invite, kicked someone, or performed a promotion/demotion
- Rank color data from `GuildControlGetRankColor` or the roster at event time

### Export / copy
- Copy visible log (or full log) to clipboard as plain text or CSV
- Useful for pasting into a spreadsheet or Discord

### Configuration panel
- In-game options: toggle which event types to capture, set `MAX_ENTRIES`, toggle the login message
- Could use a simple slash-command-driven menu or Blizzard's `Settings` panel API

### Minimap button
- Optional LibDBIcon / DataBroker button to open the window without typing `/glog`

---

## Medium-term

### Date range filter
- Filter the UI to a specific date range (e.g. "last 7 days", or custom from/to)

### Sortable columns
- Click column headers (Date, Event, Actor, Target) to sort ascending/descending

### Per-character vs per-account storage
- `SavedVariables` is currently per-account (shared across all characters)
- Add a `SavedVariablesPerCharacter` option for guilds where officers play multiple alts

### Additional event types
- Guild MOTD changes (if exposed by the API)
- Guild bank withdrawals / deposits (via `GUILDBANKFRAME_OPENED` + `GetGuildBankTransaction`)

### Membership duration + notes on leave/kick
- Track each member's join date (already captured via the JOIN entry's timestamp) and, when they LEAVE or get REMOVE(kicked), show how long they'd been a member (join date -> departure date, e.g. "4 months")
- Capture their public and officer note as of that moment on the LEAVE/REMOVE entry, since both go stale/disappear once they're off the roster (the roster snapshot scan already has this data available at diff time -- would need to snapshot it onto the entry rather than just diffing it away)

---

## Long-term / Speculative

### CSV / JSON export to file
- WoW addons can't write arbitrary files, but a FileSelectionDialog or copy-to-clipboard flow could work

### LibDataBroker integration
- Surface entry count and last event in a broker display (tooltip on hover)

### Locale support
- Extract all user-facing strings into a `locale/` table for easy translation
