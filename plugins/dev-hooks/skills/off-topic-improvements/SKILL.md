---
name: off-topic-improvements
description: Use when working through a repo's `plans/off-topic-improvements.md` backlog — the out-of-scope improvements noted during earlier work. Triggers on "drain the backlog", "address the off-topic improvements", "tackle the off-topic backlog", "work through the improvements file", or clearing accumulated backlog items. Triages each item (do now / defer / drop), lands each addressed item as its own atomic commit, and keeps the backlog file in sync. NOT for finding new improvements (that's a review) or a single ad-hoc fix.
---

# Draining the off-topic-improvements backlog

`plans/off-topic-improvements.md` collects improvements spotted mid-task and parked as
out-of-scope (the global "Suggest Improvements" rule writes to it). This skill drains that
backlog deliberately: every item ends the session **accounted for** — landed, deferred, or
dropped — and the file reflects only what's genuinely still open.

## Procedure

1. **Read the backlog.** Open `plans/off-topic-improvements.md`. Absent or empty → say so and
   stop; there's nothing to drain. Otherwise enumerate every item (a list per item, so none
   gets lost).
2. **Triage each item — do now / defer / drop — with a one-line reason.** An item is:
   - **do now** — actionable, in scope for this pass, worth the effort;
   - **defer** — still valid but blocked, too large for now, or explicitly conditional
     ("revisit if X moves in-house") — leave it in the file, untouched;
   - **drop** — stale, already done elsewhere, or not worth it — remove it, with the reason
     stated to the user.
   Present the triage and confirm scope before editing code, unless the user already said to
   just do them all.
3. **Isolate anything non-trivial.** For a "do now" item beyond a one-file edit, work in a git
   worktree (invoke [[using-git-worktrees]] / [[worktree-setup]]); trivial items can be done in
   place. Parallel-independent items can each get their own worktree/agent.
4. **One atomic commit per item.** Never bundle multiple backlog items into one commit — each
   addressed item is its own logical change, its own commit (follow the repo's commit and
   version-bump conventions).
5. **Get each change under test and verify it** before committing — tests green, and the actual
   behaviour exercised, not just eyeballed (evidence before "done"; use [[verify]] where there's
   a runtime surface). If an item can't be tested yet, say so rather than claiming it works.
6. **Keep the backlog file live.** As each item lands, **remove it** from
   `plans/off-topic-improvements.md` in that item's commit (a drained backlog is a short live
   list, not a checked-off graveyard). Dropped items are removed too; deferred items stay.
7. **Account for every item.** Close with a per-item ledger: addressed (→ commit), deferred (→
   still in file, why), dropped (→ removed, why). Nothing vanishes silently.

## Completion criteria

- Every item that was in the backlog is accounted for as **addressed / deferred / dropped** —
  no item unaddressed and unexplained.
- Each addressed item has its **own** commit and is **removed** from
  `plans/off-topic-improvements.md`.
- The file's remaining items are all genuinely still-open (deferred), each with a reason.
- Tests are green and each addressed change was actually exercised.

## Notes

- The **write** side is the global "Suggest Improvements" rule (park an out-of-scope idea in
  this file mid-task); this skill is the **read/drain** side — run it on a cadence or when the
  file has grown.
- Related: [[repo-review]] surfaces such items in the first place; this skill clears them.
