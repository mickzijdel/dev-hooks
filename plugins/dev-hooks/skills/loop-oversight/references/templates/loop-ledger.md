# Loop ledger template

Copy this into your loop's canonical file — `.claude/current_plan.md` by default, so the
`plan-reminder` and `big-change-reminder` hooks track it for free. The loop reads it at the top
of every turn and writes the row it just finished before moving on. A human reads *only this
file* to know where the loop is.

```markdown
# <Loop name> — canonical tracker

**Goal:** <one line — what "all items done" means>
**Unit of work:** <the smallest atomic item, e.g. "one feature", "one user story", "one file">
**Done-condition per item:** <checkable, e.g. "test green + row has a linked commit">
**Bound:** <max N iterations | token budget | stop after 2 consecutive empty passes>
**Phase:** <e.g. document → test → fix → re-test> (advance only when every row clears the phase)

| # | Item | Expected behaviour | Status | Findings | Evidence |
|---|------|--------------------|--------|----------|----------|
| 1 | …    | …                  | todo / in-progress / verifying / done / parked | … | commit / PR / test output |
```

## Status values (terminal = `done` or `parked`)

- `todo` — not started.
- `in-progress` — being worked this turn.
- `verifying` — work done, awaiting the **independent** verify pass (not the writing agent).
- `done` — verified, with evidence linked in the last column.
- `parked` — deliberately skipped; the Findings cell says why. Never leave a row silently blank.

## The per-turn contract (paste into the loop prompt)

> Read this ledger. Pick the first row that is not `done` or `parked`. Do that one item. Hand it
> to a separate verify pass. Update the row's Status and Evidence. Commit. Then stop this turn —
> the loop will start the next. If every row is `done`/`parked`, or the Bound is reached, stop
> the loop and report the ledger.

Keep it **one row per turn**: small, committed, reviewable. Never batch many items into one turn
or one commit.
