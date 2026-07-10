---
name: agent-brief
description: Use when writing a task brief for an agent — dispatching a subagent, handing off
  work, or turning a fuzzy request into instructions — and you want it aimed at an outcome, not
  a method. Triggers on "brief an agent", "write a task for a subagent", "spec this out for an
  agent", or a handoff that says what to do but not why or what's out of scope. Pairs with the
  intent-check hook.
---

# Agent Brief

## Overview

A good brief describes the **destination and how you'll know it's reached**, then hands over
the driving. Method-specification creeps in only when you don't trust the agent to find a good
route — the fix is a sharper target and clearer fences, not more steps. Spend your words on the
goal and the boundaries; leave the method box near-empty.

## The skeleton

Fill these in order. `METHOD` is usually the smallest box — often empty.

| Field | The question it answers |
|-------|-------------------------|
| **GOAL** | What end-state, in observable terms? (Not "improve X" — "X does Y when Z".) |
| **WHY** | What problem does this solve / who's hurting? The agent generalizes from intent when reality deviates from the plan. |
| **DONE WHEN** | How will *you* check it? Concrete inputs → expected results. If you can't state the check, the agent can't aim at it. |
| **DON'T** | Non-goals, out-of-scope, hard constraints. The negative space is where most misfires live. |
| **AUTONOMY** | Proceed freely, but stop and ask if: … (calibrate to reversibility — tighter fences on auth, migrations, deletions, anything outward-facing). |
| **PROVE IT** | What evidence back? "Ran it against the three broken inputs, pasted the output" — not "should work". |
| **METHOD** | Usually empty. If you must constrain the route, say *why*, so the reason travels to cases the rule doesn't cover. |

## Worked example

**Weak (method-shaped, uncheckable):**
> Improve the error handling in the CSV parser.

**Strong (outcome-shaped):**
> **GOAL:** Malformed CSV input yields a structured error naming the line and column; the
> parser never crashes and never swallows an error silently.
> **WHY:** Users paste broken CSVs and get a blank screen with no clue what's wrong — they
> should be able to self-diagnose.
> **DONE WHEN:** Feed it three broken inputs → three specific errors; existing tests still pass.
> **DON'T:** Touch the upload flow; add a dependency; change the v1 API.
> **PROVE IT:** Paste the three error outputs and the test run.

Note the strong version says nothing about *how* — but it's checkable, and the agent can
self-correct against it before handing back.

## The habit that compounds

When an agent does the wrong thing, patch the **brief**, not that one instance — the missing
non-goal, the vague done-criterion. Reused briefs get monotonically better; hand-corrections
don't. Before dispatching a big one, have the agent echo back its assumed goal + non-goals in
one line (contract-first) — it catches a misread for the price of a sentence.

## When NOT to use

A throwaway one-liner ("what's this function do?", "rename `foo` to `bar`") needs one line of
goal, not the skeleton. Reserve the full form for handoffs where a wrong guess is expensive:
subagent dispatches, migrations, anything hard to reverse.
