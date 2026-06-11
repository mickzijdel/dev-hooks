---
name: premortem
description: Use before committing to a non-trivial plan, design, architecture, migration, launch, or irreversible decision — especially when momentum or optimism is high and nobody has named what could go wrong. Triggers when you're about to start executing a plan, when stakes are high or the decision is hard to reverse, or when the user asks to stress-test, pressure-test, or sanity-check an approach. Not for generating ideas (that's brainstorming).
---

# Premortem

A premortem is the opposite of a postmortem: imagine the plan has **already failed**, then work backwards to find out why — before you've spent anything. It surfaces failure modes and hidden assumptions that optimism hides. This is destructive stress-testing; use [[brainstorming]] when you instead need to *generate* options.

## Procedure

1. **State the plan and a horizon.** One or two sentences, plus a date ("in 6 months").
2. **Assert the failure.** "It is now 6 months later and this was a clear, costly failure." Write from that future as fact, not possibility — this licenses honesty that "what could go wrong?" suppresses.
3. **Brainstorm causes across categories.** Force coverage, don't just list the obvious:
   - **Technical** — it didn't scale, broke under load, the approach didn't fit the problem
   - **Scope/effort** — far bigger than estimated, never finished, gold-plated the wrong part
   - **Dependencies** — an external API/library/team/data source failed or changed
   - **Ops/people** — nobody maintained it, the one person who understood it left, no one adopted it
   - **Data** — wrong/missing/dirty data, migration corrupted state
   - **Security/safety** — a hole, a permission, a destructive action with no guard
4. **Rank by likelihood × impact.** Sort so the few that matter rise to the top.
5. **Surface hidden assumptions.** For each top risk, name the belief it depends on ("assumes the API stays stable", "assumes one repo per agent"). These are the load-bearing guesses.
6. **Revise.** Produce a changed plan that defuses the top risks, plus **early-warning signals** to watch so you catch the failure early if it starts.

## Output

- **Plan & horizon**
- **Top failure modes** (ranked, with likelihood × impact)
- **Hidden assumptions** behind each
- **Revised plan** + early-warning signals to monitor

## Common mistakes

- Listing vague risks ("it might be hard") instead of specific, mechanism-level failures.
- Only covering the technical category — most real failures are scope, people, or dependency.
- Stopping at the risk list. The value is the *revised plan and the signals to watch*.
- Treating it as theater — if every risk is "low likelihood", you're not being honest about the failure.
