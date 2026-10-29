---
name: upstream-bug
description: Use when a dependency or tool you don't own is broken and needs an upstream report plus a temporary workaround. Triggers on "this is an upstream bug", "report this upstream", "work around the library bug", "pin a patched fork", or a failure traced into vendored code. Not for the repo's own bugs.
---

# Upstream Bug

Get the bug reported once, worked around minimally, and make the way back to upstream explicit.
The workaround is temporary; its exit tracker is what stops it becoming permanent: a `shortcut:`
comment beside it, or, in a fork or a shared repo, a tracking issue.

## Authority

Reproduce, draft and work around locally on your own. **Nothing outward-facing goes out
without the user's yes**: the upstream report or a comment on an existing issue, any follow-up,
an upstream PR, a pushed fork or release, the workaround PR and any tracking issue. Draft each
one, show the user the full text and what will be created where, and post only what they
approve. One ask can cover a batch they see in full. Past these limits, ask rather than judge:

- **Scope**: change only what makes the bug go away. Support the platforms this project already
  supports, not upstream's full matrix.
- **Privacy**: public artifacts carry no credentials, private prompts, private code, or
  identifying diagnostics — the reproduction is synthetic and self-contained.
- **No scheduled automation** in a fork. Disable or delete inherited scheduled workflows before
  enabling Actions.

## Procedure

1. **Reproduce** in a synthetic minimal case, and run it. A repro you haven't executed is not one.
2. **Search first**: open and closed upstream issues, PRs, discussions, and recent commits. If
   already reported, draft a comment carrying the reproduction instead of a duplicate issue.
3. **Draft the report**: plain, short sentences. Affected version, expected vs actual, complete
   minimal repro with prerequisites, invocation, and observed output; long code inside
   `<details><summary>Runnable reproduction</summary>`. A tested fix may ride along; a fix is
   not a prerequisite for reporting.
4. **Work around** with the smallest change that removes the bug:
   - Prefer a config change, version pin, or local patch over a fork.
   - If a fork is needed: base it on the release you currently use (not upstream main), publish
     it as a patch-version increment with an unmistakable name, keep runtime dependency versions
     unchanged, and pin it **immutably** (commit SHA or release checksum, plus lockfiles).
5. **Prove it**: the original repro fails before the workaround and passes after, on every
   supported platform, installed through the project's normal install path.
6. **Write the exit tracker**:
   - **A repo only the user works in**: a comment right beside the workaround (the pin, patch or
     fork reference), `shortcut: <the limit>, <when to upgrade>`, carrying the upstream report's
     link and the exact upstream change that lets you revert. It goes in the workaround commit, so
     it needs no approval of its own.
   - **A fork, or a repo shared with other people** (other committers in `git shortlog -sne`, an
     organisation's repo): draft an issue labelled `blocked` linking the upstream report, fork
     release, patch, and workaround PR, and stating what upstream change lets you revert. Link it
     from the PR with `Refs #N` — merging the workaround must not close it.
7. **Ask, then post**: show the user every draft from steps 3 and 4, and the step 6 issue if there
   is one, and post what they approve, in that order, filling in the links (the `shortcut:`
   comment's too) as each one exists.

## Disclosure

Start every GitHub message posted here (issue, comment, PR, release notes) with this line and a
blank line, putting in the name of the person whose GitHub account posts it:

`_Claude wrote and posted this comment on <account owner>'s behalf._`

## Done when

- The upstream report is posted with the user's yes, or handed to them as a draft they chose
  not to post yet.
- The workaround is in place with before/after evidence, and its PR is merged or ready (or
  drafted, if the user held it back).
- The exit tracker names the upstream link and the revert condition: the `shortcut:` comment
  beside the workaround, or, in a fork or shared repo, the `blocked` issue (or its draft, with the
  user).
- The user has the links, drafts, evidence, and any remaining limitation — or the specific
  blocker.

## Returning to upstream

When a fix ships: rerun the original repro against it, then remove the workaround and its
`shortcut:` comment, or, where a tracking issue exists, replace the workaround via PR and close the
issue only after that merges. Deleting the fork needs explicit approval.
