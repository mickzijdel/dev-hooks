---
name: board
description: Use when you want hard, independent, adversarial critique of an idea, plan, design, draft, proposal, pitch, or landing page — especially when you suspect the default response is too agreeable or sycophantic and you want real pushback before committing. Convene it on your own initiative before returning a consequential plan or draft, not only when asked. Triggers on "poke holes in this", "what am I missing", "be brutal", "convince me this is wrong", or any decision that benefits from several expert angles at once.
---

# Board of Advisors

Convene a panel of independent advisors who each attack the work from a different angle, then a chairman synthesizes. The point is to defeat agreement bias: real, separate critics surface problems a single agreeable pass glosses over.

**Engine:** spawn the advisors as **real parallel subagents** so their views are genuinely independent, not one context rationalizing with itself. **REQUIRED:** use [[dispatching-parallel-agents]] for the dispatch mechanics.

## When to use

- Before committing to a plan, design, or launch where being wrong is expensive
- When you want critique, not encouragement
- For copy/landing pages: swap in the buyer-persona panel (below)

Not for generating options ([[brainstorming]]) or imagining failure of an already-chosen plan ([[premortem]]) — though they compose well.

## How to run

1. **Gather the artifact** — the idea/plan/draft to critique, plus any context the advisors need (goal, audience, constraints). Each subagent starts cold, so include everything in its prompt.
2. **Pick the panel.** Default 5 (below). The user can override the count or the personas — honor that.
3. **Dispatch in parallel** — one subagent per advisor, all in a single message. Give each:
   - the artifact + context
   - its **persona brief** and the one lens it must argue from
   - the rule: *be harsh, specific, and evidence-based; no hedging, no praise sandwich; cite the exact part you're attacking; return your top 3–5 issues, each with a severity (blocker / major / minor) and a concrete fix.*
4. **Chairman pass** (you, main context): collect all advisor outputs, dedupe overlaps, resolve disagreements (note where advisors conflict and why), rank by severity, and deliver a verdict.

## Default panel

| Advisor | Lens |
|---------|------|
| The Skeptic | Where's the flawed reasoning, the unsupported leap, the thing that won't survive contact with reality? |
| The User | Does this solve a real problem for the person it's for? Where will they get confused, bounce, or not care? |
| The Operator | Can this actually be built, shipped, and maintained? What's the hidden cost, the thing nobody owns? |
| The Red-teamer | How does this fail, get exploited, or get beaten by a competitor? Attack it. |
| The Domain Expert | Is it technically correct and rigorous? What does someone who knows this field deeply object to? |

**Buyer-persona variant** (for landing pages, emails, proposals): replace the panel with 5 target-customer personas reviewing the copy for conversion blockers — confusion, missing proof, weak CTA, price objections, trust gaps.

## Output

- **Verdict** — ship / revise / kill, in one line
- **Blockers** then **majors** then **minors** — deduped and ranked across all advisors
- **Conflicts** — where advisors disagreed and your call on it
- **Prioritized changes** — the specific edits to make next

## Common mistakes

- Letting advisors converge — give each a *distinct* lens and the explicit no-praise rule, or you get five copies of the same take.
- Skipping the chairman pass and dumping raw advisor output — the synthesis is the deliverable.
- Spawning advisors with too little context — they can't critique what they can't see.
