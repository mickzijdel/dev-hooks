# Loop prompt scaffolds

Two prompts, kept separate on purpose: the **generate** pass produces work, the **verify** pass
confirms it. Never collapse them into one agent — the whole point is that the thing checking
isn't the thing that wrote it. Fill the `<…>` slots and drop them into `/loop`, a `/schedule`
routine, or a Workflow stage.

A third scaffold below (poll-until-true) is a lighter sibling for a different shape of loop:
not many items against a ledger, but one external condition to wait out before a single action.

## Generate pass

```
You are working through <LEDGER FILE> one item per turn.

1. Read <LEDGER FILE>. Pick the first row whose Status is not `done` or `parked`.
   If there is none, stop and report "ledger complete".
2. Do exactly that one item: <what "doing an item" means for this loop>.
3. Set the row's Status to `verifying`. Record what you did in Findings.
4. Commit just this item's change (atomic; message references the item).
5. Stop this turn. Do NOT start the next item — the loop will.

Bound: <max N iterations | stop after 2 consecutive turns with no un-done rows>.
Never batch multiple rows into one turn or one commit.
```

## Verify pass (separate agent — prompt it to refute)

```
You are the independent verifier for <LEDGER FILE>. You did NOT write this work.

For each row with Status `verifying`:
1. Try to REFUTE that the item meets its done-condition (<the checkable condition>).
   Actually exercise it — run the test, drive the feature, query the data. Do not eyeball.
2. If it holds: set Status `done` and put the evidence (test output / commit / PR) in the
   Evidence column.
3. If it fails: set Status back to `todo`, and write the concrete failure in Findings so the
   next generate turn can fix it. Default to "not verified" when unsure.

Report how many rows you moved to `done` vs bounced back to `todo`.
```

## Poll-until-true, then act

For "wait until X, then do exactly one bounded thing" — a PR merge held on CI/main settling, a
DNS or deploy check, a release finishing. There's no ledger of many items here; the item *is*
the condition. Still needs an explicit bound (an unattended poll that never gives up is as
unbounded as a ledger loop with no ceiling) and the action stays a single, named, reviewable
step — never "and then keep going with whatever's next."

```
You are waiting for <CONDITION> to become true, then you take exactly one action.

1. Check <CONDITION> (the exact command or observation — e.g. `git rev-parse origin/main`
   equals a recorded baseline AND no in-progress/queued CI runs on main; or
   `dig +short <host> A` matches the target IP AND `curl -I https://<host>` returns 200).
2. If not yet true: report the current state in one line and stop this turn — the loop will
   check again next interval. Do NOT take the action speculatively "just in case."
3. If true: take the one named action (<merge PR #N> / <report deploy is live>), then stop
   looping entirely — do not continue to unrelated work.

Bound: <max N checks | give up after <duration> and report what's still not true>.
If <CONDITION> requires comparing against a moving baseline (e.g. "has main gone quiet"),
record the baseline value explicitly before the first check — don't re-derive it each poll,
that's how a settledness check goes subtly wrong (comparing against whatever main was at
THIS check instead of the original baseline).
```

Worked examples this shape covers: "merge PR #16 once main has settled" (baseline =
`origin/main` SHA at poll start; settled = SHA unchanged across two consecutive checks AND no
queued/in-progress Actions runs); "rebase PR #46, wait for CI, merge once green" (condition =
all required checks green on the PR's HEAD); "check DNS propagation for `<host>`, then verify
HTTPS once it's switched" (condition = `dig` result matches the new IP).

## Wiring notes

- **`/loop`:** run the generate prompt on a loop; run the verify prompt as a second loop (or a
  second slash command) over the same ledger — the `verifying` status is the handoff.
- **Workflow tool:** `pipeline(rows, generate, verify)` — verify runs per row as soon as its
  generate finishes, and `budget.remaining()` is the bound. See
  [substrate-selection.md](substrate-selection.md).
- **`/schedule`:** the routine runs one bounded batch, opens a PR per `done` row, and never
  merges to `main` itself.
- **Poll-until-true:** `ScheduleWakeup` (dynamic pacing) or `/loop <interval>` both fit — the
  interval should match how fast the condition actually changes (don't poll DNS every 60s,
  don't poll a 10-minute CI run every 5 minutes). A merge action is inherently a one-time,
  reviewable step, so it's the one case in this skill where "the loop's single action is a
  merge to main" is fine — unlike the ledger loops above, there's no ongoing unattended
  work being merged, just a merge you already decided on, timed safely.
