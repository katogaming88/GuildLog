---
name: project_tww_guild_frame
description: Midnight (interface 120005) CommunitiesFrame guild log frame names and hook points
metadata:
  type: project
---

In Midnight (interface 120005), the guild log UI lives inside `Blizzard_Communities`, not `Blizzard_GuildUI`.

- **Button:** `CommunitiesFrame.GuildLogButton` — the "View Log" button in the guild pane
- **Frame:** `CommunitiesGuildLogFrame` — the frame shown when that button is clicked
- **Hook pattern:** `EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", function() CommunitiesGuildLogFrame:HookScript("OnShow", ...) end)`

**Why:** `GuildLogFrame` (the old frame) and `Blizzard_GuildUI` are not triggered by the guild pane "View Log" button in Midnight. The Communities rewrite moved everything into `Blizzard_Communities`.

**How to apply:** Any time we need to intercept or augment the guild log UI entry point, target `CommunitiesGuildLogFrame` via `Blizzard_Communities`.
