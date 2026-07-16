---
name: loop-oversight
description: Use before launching a loop that runs many iterations — a `/loop`, a `/schedule` routine, or a Workflow fan-out — or when a running loop is drifting, unbounded, or leaving no reviewable trail. Triggers on "loop over every X", "go through all the Y and track status", "automate this repetitive sweep", "run this on a schedule", or an Osman-style "make a canonical tracker and work through every item". Sets up the ledger, the bound, and the independent verify pass a loop needs to stay reviewable. NOT for a one-off task (just do it) or one-shot parallel fan-out with no iteration (that's dispatching-parallel-agents).
---

# Running loops with oversight

A loop that grinds through many items unattended is only as safe as three things: a
**ledger** you can read at a glance, an explicit **bound** it can't run past, and a **verify
pass** that isn't the same agent that did the work. Set those up *before* the loop starts.
Oversight is not watching the agent — it's making the loop's state legible in an artifact and
inserting checkpoints the loop cannot skip.

## Before you launch — five gates

Don't start the loop until each is a concrete artifact, not an intention.

1. **Ledger.** One canonical file the loop reads and writes every turn — a status table (item /
   expected behaviour / status / findings / evidence). Reuse `.claude/current_plan.md` so the
   `plan-reminder` and `big-change-reminder` hooks already track it. Template:
   [templates/loop-ledger.md](references/templates/loop-ledger.md). *Oversight = reading this
   one file.*
2. **Unit of work + done-condition.** Define the smallest atomic item and its **checkable** exit
   ("test green", "row marked done with a linked commit") — never "be thorough".
3. **Bound.** Every loop gets an explicit ceiling: max iterations, a token budget, or
   **until-N-consecutive-empty** (a plain counter misses the tail). No unbounded loops.
4. **Independent verify pass.** The agent that produces an item does not get to mark it done. A
   separate pass confirms it — an adversarial subagent prompted to *refute*, or `/code-review`.
   Mirrors `review-reminder`'s "review → fix → re-review until clean".
5. **Integration cadence.** Commit per unit (atomic — keeps `git log` the audit trail and never
   trips `big-change-reminder`). An **unattended** loop opens one PR per unit and **never
   auto-merges** — the [[commit-digest]] pattern.

## The per-turn contract

Paste this into the loop prompt so every iteration is self-checking:

> read ledger → pick next un-done item → do it → **verify (separate pass)** → update the ledger
> row with evidence → commit.

Stop when the bound is hit, or the ledger has no un-done item two turns running.

## Substrate — match it to how much you can watch

| You are… | Use | Bound + oversight |
|---|---|---|
| At the keyboard | `/loop` (interval or self-paced) | Ctrl-C; Stop hooks (`verify-work`, `review-reminder`) gate each turn |
| Present, want structure | Workflow tool | `budget.remaining()` ceiling; verify stage baked into the pipeline |
| Away / recurring | `/schedule` cron routine | PR-per-unit, no auto-merge, a digest you read later |

Detail and the budget/until-dry patterns: [substrate-selection.md](references/substrate-selection.md).
Ready generate + verify prompts, plus a poll-until-true scaffold for "wait for a condition, then
take one action" (merge once CI/main settles, confirm a deploy went live):
[prompt-scaffolds.md](references/prompt-scaffolds.md).

## Completion criteria

- All five gates existed as artifacts **before** the loop ran (ledger file, defined unit,
  written bound, verify pass, commit/PR cadence).
- Every ledger row reaches a terminal state with **linked evidence** (commit / PR / test
  output), or is explicitly parked with a reason — no silent skips.
- The loop stopped at its bound, not by running out of context or being interrupted.

## Red flags — stop and add a gate

- No ledger file, or the loop isn't updating it each turn → oversight is invisible.
- "I'll just let it run and check the result" with no iteration/budget ceiling → unbounded.
- The same agent writes an item and marks it done → no independent verify.
- An unattended loop merging to `main` → review can never happen.

## Notes

- **The bound lives where you write it.** A Stop hook can't hard-cap a `/loop` (it can only nudge
  the next turn) and can't see token counts. The real ceiling is `max iterations` /
  `until-N-empty` in the prompt, or `budget.remaining()` in the Workflow tool.
- For a batch sweep across many targets, the `dev-env-setup` **fleet mode** (canary first → one
  isolated agent per target → verify each) is the supervised template — reuse that shape.
- Related: [[multi-session-plans]] owns the `.claude/current_plan.md` phased checkpoint this
  skill uses as a ledger; [[repo-review]] and ad-hoc work surface the items a loop then works.
