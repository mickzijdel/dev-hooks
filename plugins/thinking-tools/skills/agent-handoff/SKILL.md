---
name: agent-handoff
description: Use when starting a new Claude session to continue work a previous agent or session started, or when coordinating parallel agents. Provides a plan.md format and handoff protocol so sessions can resume without re-explaining context. Triggers on "pick up where we left off", "continue the plan", "hand off to another agent", "what's next in the plan", "coordinate agents", or when a plan.md already exists at session start.
---

# Agent Handoff

A repeatable pattern for continuing work across sessions or coordinating multiple agents: use a `plan.md` as the shared, living record. One agent writes and updates it; another reads and executes. The `plan-reminder.sh` hook in `dev-hooks` enforces this at session end — it fires if a plan file exists but is unchanged, catching the drift where an agent works all session but never updates the shared record.

## When to use

- Starting a new session to continue in-progress multi-session work
- Handing off to a fresh agent after a long session is about to context-compress
- Coordinating two parallel agents: one plans, one executes
- Resuming a multi-day project without re-explaining context from scratch

## The plan.md format

Store at `.claude/current_plan.md` (where `plan-reminder.sh` looks) or at the repo root as `plan.md`, depending on whether this is project-level or session-level coordination:

```markdown
# Plan: <short name for the work>

## Goal
One sentence. What does done look like, and how will you verify it?
Good: "All 14 tests pass and `bin/rails test` exits 0 with no skips."
Bad: "Implement the feature."

## Context
Key facts the executing agent needs that aren't in the code:
- Relevant constraint or prior decision
- File:line pointers for non-obvious locations
- Anything that bit the previous session

## Tasks
- [x] Completed task
- [ ] Current task (in progress)
- [ ] Next task
- [ ] ...

## Status
Last updated: YYYY-MM-DD HH:MM
Current state: brief summary of where things stand
Blockers: none / describe what's stuck and what's needed
Next action: the exact first step for the next session or agent
```

## Starting a session from a plan

When you open a session and see a plan file:

1. Read it in full before touching any code.
2. Check `## Status` — what's the current state and next action?
3. Scan completed `[x]` tasks to understand what's already done.
4. Begin from the first unchecked `[ ]` task, unless `Status` says otherwise.
5. Update `## Status` and mark tasks `[x]` as you go — not just at session end.

If anything in the plan is ambiguous, add a "Clarification needed" line to `## Status` before proceeding — don't silently pick an interpretation that might be wrong.

## Coordinating parallel agents

**Agent A (planner):** writes the full plan (goal, context, all tasks). Commits or writes it to disk. Signals Agent B to start.

**Agent B (executor):** reads the plan, works through unchecked tasks in order, updates `## Status` after each task completes, marks tasks `[x]` as it goes, adds blockers to `## Status` if stuck.

For a looping Agent B (e.g. a recurring remote agent), the loop body is:
1. Read `## Status`.
2. If `Current state` says waiting or blocked, stop and signal Agent A.
3. Otherwise, execute the next `[ ]` task, update `## Status`, mark `[x]`, and loop.

## The handoff note (outgoing agent)

Before ending a session mid-task, update the plan:

```markdown
## Status
Last updated: 2026-06-13 14:30
Current state: Completed tasks 1–3 (auth refactor). Task 4 (rate limiting) is half-done:
`rate_limit` call is in sessions_controller.rb but the handler method is missing.
Tests are red on that file.
Blockers: none
Next action: Add `rate_limit_exceeded` private method to SessionsController, run
`bin/rails test test/controllers/sessions_controller_test.rb`, then continue to task 5.
```

A good handoff note lets the next session start immediately without reading the diff.

## Connection to plan-reminder.sh

`dev-hooks`' `plan-reminder.sh` Stop hook fires when `.claude/current_plan.md` exists at session end but hasn't changed since the session started. Its purpose is to catch the case where an agent worked all session but forgot to update the shared record. This skill describes *how* to write a good update — the hook just enforces that you do.

## Tips

- **Write the Goal as a verification statement.** "Tests pass and the command exits 0" beats "implement the feature" — it tells the next agent exactly what to check.
- **Update Status during the session, not just at the end.** If you're about to context-compress, update Status first so the compressed context still reflects reality.
- **Keep Context lean.** Three targeted bullets beat a paragraph of backstory. Context is for what the code doesn't make obvious; the code itself is the record of what was done.
- **Don't over-decompose tasks.** A task should be a meaningful unit of work, not a single function call. A plan with 40 micro-tasks is hard to read at a glance.
