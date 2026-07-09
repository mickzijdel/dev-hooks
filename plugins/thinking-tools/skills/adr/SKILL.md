---
name: adr
description: Use when making a significant architectural or technical decision that shouldn't be re-litigated later — choosing a tool, pattern, or approach with real trade-offs. Write one ADR per decision, proactively the moment such a decision lands — don't wait to be asked. Triggers on "record this decision", "why did we choose X", "document our approach to Y", "write an ADR", or when completing a decision that cost real deliberation (library selection, database strategy, auth approach, deployment model).
---

# Architecture Decision Records (ADRs)

An ADR is a short document that captures a significant technical decision — why it was made, what alternatives were weighed, and what consequences to expect. Its value is institutional memory: future contributors (and future Claude sessions) don't re-litigate settled questions, and the reasoning doesn't disappear as the decision fades into obvious-seeming background.

**Write one when the decision:**
- is hard to reverse or expensive to undo
- cost real deliberation (alternatives existed)
- will surprise someone reading the code later
- defines a constraint that future decisions must respect

Don't write one for every choice — only the ones worth recording.

## Format

Use the lightweight Nygard format — context + decision + consequences, in a short Markdown file.

```markdown
# NNNN — Title in plain words

**Date:** YYYY-MM-DD  
**Status:** Accepted | Deprecated | Superseded by [ADR-MMMM](MMMM-title.md)

## Context

What situation prompted this decision? What constraints, requirements, or pressures existed?
What were the realistic alternatives and their trade-offs?

## Decision

The choice made. One or two sentences, stated directly.

## Consequences

What becomes easier, harder, or required as a result?
Downstream impacts, known limitations, things to watch for.
```

## Where to store them

Place ADRs in `docs/decisions/` (create it if absent), named `NNNN-short-title.md` — sequential, lowercase, hyphens. Keep a `docs/decisions/README.md` index:

```markdown
# Decisions

| # | Title | Date | Status |
|---|-------|------|--------|
| 0001 | Use PostgreSQL as primary datastore | 2025-01-10 | Accepted |
| 0002 | Prefer mise for tool management | 2025-03-01 | Accepted |
```

If the project uses `CLAUDE.md`, add a one-line summary of active ADRs there so they surface as context without requiring a full file read.

## Writing a good ADR

**Context:** write for someone who wasn't in the room. Include the constraint or tension that made this a real decision, not just "we needed to pick something." Name the alternatives you seriously considered.

**Decision:** be specific and direct. "We chose X" — not "we may use X."

**Consequences:** be honest about what you're giving up, not just what you're gaining. List follow-up work the decision requires.

**Status:** update it when a decision is revisited. Superseded ADRs stay in the repository — they explain why things changed.

## When NOT to write one

- Routine implementation details (naming a method, choosing a gem version)
- Decisions that will obviously need revisiting frequently (configuration values)
- Things the code itself explains clearly (file structure, obvious patterns)

## Composing with other skills

- Before committing to the decision, run [[board]] to stress-test it from multiple angles.
- After identifying a risk, run [[premortem]] to imagine failure modes.
- When a decision hardens a domain term (or vice versa), run [[domain-modeling]] — the term goes in `CONTEXT.md`, the decision goes here.
- For active work-in-progress coordination across sessions, use `plan.md` (see [[agent-handoff]]) — ADRs record settled decisions; `plan.md` tracks live work.
