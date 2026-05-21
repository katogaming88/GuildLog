---
name: feedback_branch_before_changes
description: Before making any code changes, check the current branch — if on main, create a new branch first
metadata:
  type: feedback
---

Before making any changes, check the current git branch. If on `main`, create and switch to a new branch before proceeding.

**Why:** User wants to follow the project branching rules (CLAUDE.md) consistently — all non-doc changes must go through a branch and PR, never directly to main.

**How to apply:** At the start of any task that involves editing files, run `git branch --show-current`. If it returns `main`, ask the user for a branch name or propose one following the `<type>/<short-description>` convention, create it, and switch to it before touching any files.
