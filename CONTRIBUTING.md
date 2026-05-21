# Contributing

Contributions are welcome — bug fixes, new features from the roadmap, or anything that improves the addon.

---

## Getting started

1. Fork the repository and clone it locally.
2. Copy (or symlink) the `GuildLog/` folder into your WoW AddOns directory:
   ```
   World of Warcraft/_retail_/Interface/AddOns/GuildLog/
   ```
3. Launch WoW (or `/reload` if it's already running) to load the addon.
4. Make your changes, then `/reload` in-game to test.

No build step, no dependencies — it's plain Lua loaded directly by the WoW client.

---

## Reporting bugs

Use the **Bug report** issue template. The most useful thing you can include is the relevant section of your `SavedVariables` file:

```
WTF/Account/<name>/SavedVariables/GuildLog.lua
```

---

## Suggesting features

Use the **Feature request** issue template. Check `ROADMAP.md` first — if it's already listed there, a thumbs-up on the existing issue is more useful than a duplicate.

---

## Opening a pull request

Open an issue first for anything non-trivial so the approach can be agreed on before you invest time writing it.

The PR template will prompt you for everything required. Short version:

- One feature or fix per PR — keep diffs focused
- Update `CHANGELOG.md` under a new `[Unreleased]` section
- If completing a roadmap item, remove or update that entry in `ROADMAP.md`
- Pass all items on the manual testing checklist in the PR template

---

## Versioning

This project follows [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`). The rules below are intentionally WoW-addon-specific:

| Part | Bump when… | Example |
|---|---|---|
| `MAJOR` | The `GuildLogDB` SavedVariables schema changes in a way that requires users to run `/glog clear` | Adding a required field with no default, renaming `entries` |
| `MINOR` | New user-visible feature is added, backward-compatible with existing saved data | New filter type, export button, minimap icon |
| `PATCH` | Bug fix, WoW patch compatibility update, documentation or CI change only | Dedup fix, TOC interface bump, README update |

**Pre-1.0 note:** While the version is `0.x.x`, minor versions may include breaking SavedVariables changes without a MAJOR bump — this period is for establishing the schema. Once the schema is stable, `1.0.0` will be tagged and the full rules above apply.

### What to update when bumping the version

1. `## Version` in `GuildLog.toc`
2. The `[Unreleased]` section header in `CHANGELOG.md` → rename it to the new version and date
3. The version badge URL in `README.md`

### Releasing

Push a version tag and the `release` workflow handles the rest:

```
git tag v0.1.0
git push origin v0.1.0
```

The workflow zips the addon files and creates a GitHub release using the matching section of `CHANGELOG.md` as the release body.

---

## Code style

- Local variables wherever possible; avoid polluting the global namespace beyond `GuildLog` and `GuildLogUI`
- UI construction lives in `GuildLogUI.lua`; data/event logic lives in `GuildLog.lua`
- Comments only for the *why* — hidden constraints, non-obvious invariants, workarounds. Never describe what the code does.
- No external libraries without prior discussion
