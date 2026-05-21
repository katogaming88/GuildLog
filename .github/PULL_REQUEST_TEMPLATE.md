## What does this PR do?

<!-- One or two sentences. Link to the issue it closes if applicable: "Closes #123" -->

---

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Refactor (no behavior change)
- [ ] Documentation only

---

## Testing

<!-- Describe what you tested manually. Check every box that applies. -->

- [ ] Log shows entries after a guild event fires
- [ ] `/reload` does not produce duplicate entries
- [ ] Log-out / log-in does not produce duplicate entries
- [ ] Timestamps reflect the actual event time, not the login time
- [ ] Filters and search work correctly
- [ ] Clear Log empties both the display and the saved variable
- [ ] `/glog debug` reports the correct entry count

---

## Checklist

- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] If a roadmap item: `ROADMAP.md` updated to reflect completion
- [ ] TOC `## Interface:` matches the current live patch (if changed)
- [ ] No new globals introduced outside of `GuildLog` / `GuildLogUI`
