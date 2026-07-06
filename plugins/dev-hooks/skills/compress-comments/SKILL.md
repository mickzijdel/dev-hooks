---
name: compress-comments
description: |
  Use when a session's work left verbose or redundant code comments to clean up — after
  finishing a feature, before commit/merge, when the compress-comments-reminder hook fires,
  or when asked to "compress the comments", "clean up your comments", or "review the
  comments you added". NOT for reviewing code structure (use code-simplifier) or whole-repo
  audits (use repo-review).
allowed-tools:
  - Read
  - Edit
  - MultiEdit
  - Bash
  - Grep
  - Glob
---

# compress-comments

Review the comments this session's work added and cut them down. AI-authored comments skew
verbose: they restate the code, narrate the change, or argue with an imagined reviewer. One
rule decides everything:

> **A comment survives only if it states something the code cannot show** — a constraint,
> invariant, gotcha, why-not-the-obvious-way, spec/issue link, or domain fact.

Delete-biased: when in doubt, delete. Compress only when a real "why" is buried in
verbosity — keep the why, drop the narration.

## Find the comments

Judge only comments on lines this session's work added or changed. Never touch pre-existing
comments.

- **On a feature branch**: `git diff $(git merge-base main HEAD)` for committed work plus
  `git diff HEAD` for uncommitted work (substitute `master` where that's the default branch).
  Untracked new files are entirely yours — review all their comments.
- **On the default branch itself**: review the commits you remember making this session
  (`git log --oneline` to jog memory; your commits carry the Claude co-author trailer), plus
  the uncommitted diff.

## Dispositions

| Disposition | When |
|---|---|
| **Delete** (default) | The comment fails the survival rule: code-echo, change narration, planning forensics, reviewer justification, section headers, leftovers — see [references/comment-smells.md](references/comment-smells.md) for the taxonomy with examples. |
| **Compress** | A real why is buried in narration: rewrite to just the constraint, usually one line. |
| **Docstring-compress** | Public-API docstrings (Python docstrings, JSDoc, YARD, rustdoc) are never deleted — doc tooling and linters expect them. Drop parameter/return lines that restate names and types; keep the one-line summary and real semantics (units, side effects, invariants, raised errors). |

## Never touch

- **Directive comments**: `shellcheck`, `eslint-disable`, `noqa`, `type: ignore`, `rubocop:`,
  `jscpd:ignore-*`, `frozen_string_literal`, coverage/formatter pragmas. Even one that looks
  wrong or unnecessary — removing a suppression is a behavior change, not comment cleanup;
  flag it in the summary instead.
- License headers, shebangs, encoding lines.
- TODOs with real content (an empty or stale TODO is a leftover — delete it and flag it in
  the summary so the intent isn't silently lost).
- Code. This skill edits comments only.

## Workflow

1. Collect the added/changed comments from the diff (above).
2. Judge each against the survival rule; categorize borderline ones with the taxonomy in
   [references/comment-smells.md](references/comment-smells.md).
3. Apply the edits directly — no approval round-trip.
4. Verify: the new diff-of-the-diff is comment-only (no code lines changed), and any linter
   or formatter that watches comments (docstring linters, `shfmt`) still passes.
5. Report a compact summary: counts deleted/compressed, one or two representative examples,
   plus anything flagged (suspect directives, dropped TODOs).
