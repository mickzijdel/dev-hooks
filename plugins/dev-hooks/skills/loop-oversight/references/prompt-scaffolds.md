# Loop prompt scaffolds

Two prompts, kept separate on purpose: the **generate** pass produces work, the **verify** pass
confirms it. Never collapse them into one agent — the whole point is that the thing checking
isn't the thing that wrote it. Fill the `<…>` slots and drop them into `/loop`, a `/schedule`
routine, or a Workflow stage.

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

## Wiring notes

- **`/loop`:** run the generate prompt on a loop; run the verify prompt as a second loop (or a
  second slash command) over the same ledger — the `verifying` status is the handoff.
- **Workflow tool:** `pipeline(rows, generate, verify)` — verify runs per row as soon as its
  generate finishes, and `budget.remaining()` is the bound. See
  [substrate-selection.md](substrate-selection.md).
- **`/schedule`:** the routine runs one bounded batch, opens a PR per `done` row, and never
  merges to `main` itself.
