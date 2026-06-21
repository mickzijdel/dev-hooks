---
name: grill-me
description: Adversarial code review — finds bugs, logic errors, missing edge cases, and security vulnerabilities by dispatching parallel subagents each attacking the code from a different angle, then synthesizing findings ranked by severity. Distinct from code-simplifier (which improves style/clarity) and board (which critiques ideas). Triggers on "grill me on this", "find bugs in this", "poke holes in my code", "what could go wrong here", "adversarial review", or "find edge cases in this".
---

# Grill Me

Dispatch a panel of adversarial code reviewers, each attacking the code from a single angle,
then a chairman synthesizes their findings. The point is to break agreement bias: real separate
critics find problems a single agreeable pass glosses over.

**Engine:** spawn the reviewers as **real parallel subagents** so their attacks are genuinely
independent, not one context rationalizing with itself. **REQUIRED:** use
[[dispatching-parallel-agents]] for the dispatch mechanics.

## When to use

- Before merging a non-trivial implementation where being wrong is expensive
- When you want the code actually attacked, not just reviewed politely
- After implementing something subtle (auth, concurrency, money, state machines)

Not for style improvements ([[code-simplifier]]) or idea critique ([[board]]).

## How to run

1. **Gather the target** — the diff, file, or function to attack. If not specified, use the
   current working diff (`git diff HEAD`). Each subagent starts cold, so include the full
   relevant code in its prompt.
2. **Dispatch in parallel** — one subagent per reviewer, all in a single message. Give each:
   - the full code to attack
   - its **persona brief** and the one attack lens it must argue from
   - the rule: *be specific and evidence-based; no hedging; cite the exact line or pattern
     you're attacking; return your top findings, each with a severity (blocker / major / minor)
     and a concrete fix.*
3. **Chairman pass** (you, main context): collect all reviewer outputs, dedupe overlaps, resolve
   disagreements (note where reviewers disagree and why), rank by severity, and deliver the
   verdict.

## Default panel

| Reviewer | Lens |
|----------|------|
| The Bug Hunter | Logic errors, wrong conditionals, off-by-ones, nil/null/zero mishandling, incorrect assumptions about data types or ordering |
| The Security Auditor | Injection (SQL, command, template), auth bypass, insecure direct object references, SSRF, exposed secrets, session fixation, missing CSRF protection |
| The Edge-Case Seeker | Boundary values, empty/nil/zero inputs, concurrent access and race conditions, very large inputs, unusual-but-valid data that breaks assumptions |
| The Performance Skeptic | N+1 queries, blocking calls on hot paths, unnecessary allocations, missing indices, unbounded loops on user-controlled input |

Scale the panel to the complexity of the code: a 20-line helper needs the Bug Hunter and the
Edge-Case Seeker; a payment flow needs all four plus a fifth (a Domain Expert briefed on the
specific domain invariants).

## Output

- **Verdict** — safe to merge / needs fixes / do not merge, in one line
- **Blockers** then **majors** then **minors** — deduped and ranked across all reviewers, each
  citing the exact line or pattern and a concrete fix
- **Conflicts** — where reviewers disagreed and your call on it

## Common mistakes

- Grilling a diff that doesn't include enough context — fetch the callers or the full function
  if the logic spans more than what's in the diff
- Accepting a "no issues found" from a subagent without asking it to try harder — push back
  once with "assume there is at least one issue; find it"
- Running this on style issues — use [[code-simplifier]] for that
