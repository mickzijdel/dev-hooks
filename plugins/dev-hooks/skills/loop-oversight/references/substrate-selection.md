# Choosing the loop substrate

Three ways to run a loop, ordered by how much you can watch it. Pick by presence, then wire the
bound the substrate gives you.

## `/loop` — in-session, supervised

Runs a prompt or slash command on an interval (`/loop 5m /foo`) or self-paced (no interval → the
model paces itself via a scheduled wakeup). You're present: you can read the ledger between turns
and Ctrl-C.

- **Bound:** state it in the prompt — `max N iterations`, or `stop after 2 consecutive turns that
  find nothing new`. `/loop` won't stop itself otherwise.
- **Oversight for free:** the dev-hooks Stop hooks fire on every turn — `verify-work` runs
  linters/tests, `review-reminder` nudges a review, `change-summary-reminder` forces a
  plain-language per-file account. A well-behaved loop (commits per unit) never trips
  `big-change-reminder`.
- **Best for:** iterating over a known work-list while you're around — the Osman "document every
  feature, then test each, then fix" sweep.

## Workflow tool — structured, budget-capped

Deterministic fan-out/pipeline in the harness. Verification is a *stage*, not an afterthought.

- **Bound:** `budget.remaining()` is a hard ceiling — `while (budget.total && budget.remaining()
  > 50_000) { … }`. Or **loop-until-dry**: keep dispatching finders until K consecutive rounds
  return nothing new.
- **Independent verify baked in:** the canonical shape is
  `pipeline(items, generate, verify)` — each item's verify runs the moment its generate finishes,
  by a *different* agent (prompt it to refute).
- **Best for:** a sweep you want reproducible and cost-bounded, where "generate" and "verify"
  must not be the same agent.

## `/schedule` — unattended, recurring

Cloud cron routine (a "routine") that runs with no one watching. Oversight has to be **async**,
because you're not there when it runs.

- **Bound:** the routine does one bounded batch per run; don't let a single run loop unbounded.
- **Async oversight is mandatory:** **one PR per unit, never auto-merge to `main`.** You review
  on your clock, not the agent's. Emit a digest/report each run. This is exactly what
  [[commit-digest]] does (a PR per adopted change) and what [[weekly-automation-review]] produces
  (a report you read Monday).
- **Best for:** recurring maintenance — watch upstream repos, drain a backlog weekly, re-run a
  health check.

## Decision

- Present and want to watch → **`/loop`**.
- Present but want structure + a hard cost cap → **Workflow tool**.
- Away / it should recur on a schedule → **`/schedule`** with PR-per-unit.

In every case the non-negotiables are the same: a ledger, an explicit bound, and a verify pass
that isn't the writing agent.
