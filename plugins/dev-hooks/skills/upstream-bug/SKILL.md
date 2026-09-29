---
name: upstream-bug
description: Use when a third-party dependency or tool you don't own is broken and you need an upstream
  report plus a temporary workaround. Triggers on "this is an upstream bug", "report this upstream",
  "work around the library bug", "pin a patched fork", or a failure traced into vendored/managed
  code. Not for bugs in the repo itself.
---

# Upstream Bug

Get the bug reported once, worked around minimally, and make the way back to upstream explicit.
The workaround is temporary; the tracking issue is what stops it becoming permanent.

## Authority

Fix, report, and pin autonomously **within these limits** — anything past them is a question
to the user, not a judgment call:

- **Only contact** with third parties is the one initial upstream report. No follow-up comments,
  replies, upstream PRs, or other outreach without permission. Your own fork, release, tracking
  issue, and workaround PR are yours to create.
- **Scope**: change only what makes the bug go away. Support the platforms this project already
  supports, not upstream's full matrix.
- **Privacy**: public artifacts carry no credentials, private prompts, private code, or
  identifying diagnostics — the reproduction is synthetic and self-contained.
- **No scheduled automation** in a fork. Disable or delete inherited scheduled workflows before
  enabling Actions.

## Procedure

1. **Reproduce** in a synthetic minimal case, and run it. A repro you haven't executed is not one.
2. **Search first**: open and closed upstream issues, PRs, discussions, and recent commits. If
   already reported, post the reproduction there instead of filing a duplicate (still the one
   allowed contact).
3. **Report**: plain, short sentences. Affected version, expected vs actual, complete minimal
   repro with prerequisites, invocation, and observed output; long code inside
   `<details><summary>Runnable reproduction</summary>`. A tested fix may ride along; a fix is
   not a prerequisite for reporting.
4. **Work around** with the smallest change that removes the bug:
   - Prefer a config change, version pin, or local patch over a fork.
   - If a fork is needed: base it on the release you currently use (not upstream main), publish
     it as a patch-version increment with an unmistakable name, keep runtime dependency versions
     unchanged, and pin it **immutably** (commit SHA or release checksum, plus lockfiles).
5. **Prove it**: the original repro fails before the workaround and passes after, on every
   supported platform, installed through the project's normal install path.
6. **Track the exit**: open an issue labelled `blocked` linking the upstream report, fork
   release, patch, and workaround PR, and stating what upstream change lets you revert. Link it
   from the PR with `Refs #N` — merging the workaround must not close it.

## Disclosure

Start every GitHub message an agent writes here (issue, PR, release notes) with
`> This was written by an agent. Model: <runtime model ID>.` and a blank line.

## Done when

- The upstream report is published (or the existing one carries your repro).
- The workaround PR is merged (or ready, if merging isn't yours) with before/after evidence.
- The `blocked` tracking issue exists and names its revert condition.
- The user has the links, evidence, and any remaining limitation — or the specific blocker.

## Returning to upstream

When a fix ships: rerun the original repro against it, replace the workaround via PR, close the
tracking issue only after that merges. Deleting the fork needs explicit approval.
