# GuildLog — project rules

## Changelog

- **Update trigger**: update `CHANGELOG.md` on every PR, not every individual commit.
- **Format**: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) — use only these sections where relevant: `Added`, `Fixed`, `Changed`, `Removed`.
- **Versioning**: Semver (`MAJOR.MINOR.PATCH`).
  - `PATCH` — bug fixes with no new user-visible behaviour.
  - `MINOR` — new features or user-visible behaviour changes (backwards-compatible).
  - `MAJOR` — breaking changes (e.g. SavedVariables schema change that wipes existing data).
- **Author**: Anyone may write an entry. Add your name after the date on the version header line:
  ```
  ## [1.2.3] — 2026-05-21 — YourName
  ```
- **TOC sync**: bump `## Version:` in `GuildLog.toc` to match whenever the changelog version changes.

## Branching

Pattern: `<type>/<short-description>` — same types as PR titles, lowercase kebab-case (e.g. `fix/timestamp-reading`, `feat/date-range-filter`).
Always branch off `main`; PR back to `main`.

- **Doc-only changes** (`docs` type — CHANGELOG, CONTRIBUTING, CLAUDE.md, comments): may be pushed directly to `main`, no PR required.
- **Everything else**: must be on a branch with a PR — no direct pushes to `main`.

## PR titles

Follow Conventional Commits — `<type>: <short description>` (imperative mood, under 72 chars, no trailing period).
Types: `feat` (minor bump), `fix` (patch bump), `docs`, `chore`, `refactor`, `perf`.
Append `!` for breaking changes → major bump (e.g. `feat!: restructure GuildLogDB schema`).
Full details in `CONTRIBUTING.md`.
