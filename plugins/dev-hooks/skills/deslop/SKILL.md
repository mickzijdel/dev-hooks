---
name: deslop
description: |
  Use before declaring a coding task done, before a commit, or before merging — and when
  asked to "deslop", "de-LLMify", "remove the AI slop", "make this look human-written", or
  "clean up your code". Also when a diff grew a file, added fallbacks or defensive checks,
  piled on comments, or duplicated logic the repo already has. Behaviour-preserving
  cleanup of AI-authored slop in the current diff, run by a fresh-context subagent. NOT
  for new features, redesigns, or comment-only cleanup (use compress-comments).
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Agent
---

# deslop

Strip AI slop from **the current diff** without changing behaviour. Slop is code that
passes its tests today and becomes a liability later: verbosity, defensive scaffolding,
fallbacks that never fire, and comments nobody would have written by hand.

**The pass is always run by a subagent.** You scope the diff and dispatch. You do not do
the cleanup yourself — see [Why a subagent](#why-a-subagent).

## Steps

1. **Scope the diff.** On a branch, `git diff $(git merge-base main HEAD)` plus
   `git diff HEAD` for uncommitted work; untracked new files count entirely. On the
   default branch, this session's commits plus the uncommitted diff. Never the whole repo
   — that is [[repo-review]].
2. **Run the scanner** over the changed files:
   `scripts/slop_scan.py <file>...` (`--metrics-only` for the measurement table alone).
   It exits 1 when it has findings. Its output goes into the brief verbatim.
3. **Run the complexity check** for the changed files' language (see
   [Complexity](#complexity)). Its output goes into the brief too.
4. **Dispatch one subagent** with the prompt below, filled in. Wait for it.
5. **Report** what came back: lines before → after, Tier A count, each Tier B fix, each
   Tier C proposal, and the verification command with its result.

Done when every changed file has been through the pass, the diff is no longer than it
started, and the test command that passed before passes after.

## The subagent brief

Dispatch with `subagent_type: "general-purpose"`. Copy this verbatim, filling the four
bracketed slots:

```
Remove AI-authored slop from a diff. Preserve behaviour exactly.

SCOPE — only these files, nothing else in the repo:
[file list]

THE DIFF:
[git diff output, or the command that produces it]

SCANNER FINDINGS (mechanical, from slop_scan.py — a prompt to look, not a verdict;
some are wrong, say so rather than "fixing" them):
[slop_scan.py output]

COMPLEXITY CHECK (a Tier C observation, not a Tier A edit — propose decompositions,
change nothing; an irreducible dispatch table is a fair answer, say so):
[complexity tool output, or "none configured for this language"]

VERIFY WITH: [test command]

Read these first: the tier catalogue at
plugins/dev-hooks/skills/deslop/references/patterns.md, and the measured comment
budgets at plugins/dev-hooks/skills/deslop/references/measurements.md.

METHOD
1. Run the verify command now and record the result. If it is already failing, stop and
   report that — do not clean up on top of a broken baseline.
2. Work the tiers in order, re-running the verify command after each.
   - Tier A: delete. No permission, no report per item.
   - Tier B: fix, and record each one.
   - Tier C: propose in writing. Do NOT restructure.
3. Before deleting or keeping any exported symbol, grep its callers. "It might be used
   elsewhere" is a reason to look, not a reason to keep.

HARD RULES
- The diff must end shorter than it started, or equal. If it grew, you did it wrong.
- Never add an abstraction during cleanup. No new Utils/Helper/Manager, no wrapper that
  only forwards. Extraction is a Tier C proposal, not an action.
- Never touch lint or tooling directives (noqa, shellcheck, eslint-disable, type: ignore,
  rubocop:, jscpd:ignore-*, frozen_string_literal). Removing a suppression is a behaviour
  change. Flag it instead.
- Never touch code outside SCOPE, and never change what the code does.
- A public-API docstring is compressed, never deleted.

COMMENTS
Apply the survival rule — a comment survives only if it states something the code cannot
show — and then the budget. Over ~15% comment density, ranking replaces filtering: keep
the few that carry a real constraint, delete the rest, even though each would pass the
rule on its own. Rewrite survivors as fragments that name identifiers: human codebases
run 7-8 words per comment with under 1% em dashes, against 12 words and 19% in
AI-written code. No em dashes, no parenthetical asides, no balanced clauses.

REPORT BACK
- lines before → after
- Tier A: count only
- Tier B: each fix, with file:line and why it was a latent bug
- Tier C: each proposal, concrete, with the file names a split would produce
- the verify command and its actual output
- anything the scanner flagged that you judged a false positive, and why
```

## Complexity

`slop_scan.py` measures verbosity. It does not measure the other half — complexity
concentrating in a few functions — because a regex approximation of a cyclomatic count
was built, measured against the reference corpora, and cut: it separated human from AI
code about 2×, against 5× for comment density, and would have doubled the scanner's whole
false-positive budget. The numbers are in
[references/measurements.md](references/measurements.md).

Real AST tools do this properly, so run the one the project already has:

| Language | Command |
|---|---|
| Python | `ruff check --select C901 --config "lint.mccabe.max-complexity = 10" <files>` |
| JS/TS | `eslint --rule '{"complexity": ["warn", 10]}' <files>` |
| Go | `gocyclo -over 10 <files>` |
| Ruby | `rubocop --only Metrics/CyclomaticComplexity <files>` |

A function over the threshold is a **Tier C** observation — propose the decomposition,
don't perform it. Complexity is a code-quality signal rather than an authorship one: a
15-branch function earns a look whoever wrote it, and some genuinely are irreducible
dispatch tables. Say which when that is the case.

If the project has no such tool configured, skip this step and say so — do not install
one during a cleanup pass.

## Why a subagent

The agent that wrote the code is the worst reader of it. It knows why every comment is
there, so every comment looks necessary; it remembers deciding each fallback was prudent.
A fresh context has none of that and sees what a reviewer would see on Monday. This is
the same reason [[design-process]] gives its design critic a clean context.

It also keeps a long implementation session from spending its remaining context on
cleanup.

## Rationalisations

| Excuse | Reality |
|---|---|
| "The comments are fine, each one is true" | True is not the bar — every comment in a 50%-density file was true. Over budget, rank them. |
| "I'll deslop it myself, dispatching is overhead" | You wrote it. You cannot see it. That is the whole point. |
| "A fallback is safer" | A fallback that never fires hides bugs and doubles the paths a reader must hold. Trusted path, no check. |
| "The scanner flagged it, so it's slop" | It is a regex. Judge each finding; report the ones it got wrong. |
| "I'll extract a helper while I'm in here" | Not during cleanup. Deletion-first; propose extraction as Tier C. |
| "Tests pass, it's clean" | SlopCodeBench: agent code passes its tests and still erodes structurally in 80% of trajectories. |
| "It's only 20 lines, not worth a pass" | Then the pass costs nothing. Run it. |
| "The diff got longer because the fix needed it" | Then it was not a cleanup. Separate the fix from the pass and say so. |

## Scope

Not for: new features, redesigns, or general refactoring with no simplification intent.
Comment-only cleanup is [[compress-comments]]. Whole-repo audits are [[repo-review]].
Behaviour bugs are `/code-review`. A Tier C proposal that gets accepted is its own task,
run afterwards with [[codebase-design]].

---

**Credit:** the Tier A/B/C structure, the shrinking-diff invariant, and much of the
catalogue are adapted from [Andrii Paslavskyi's `anti-slop`
plugin](https://github.com/paslavskyi/anti-slop) (MIT). The failure modes behind it come
from [SlopCodeBench](https://arxiv.org/html/2603.24755v1) and Mike Mason's [The Code
You're Not Reading](https://mikemason.ca/writing/ai-slop-code-april-2026/). The comment
density and register budgets are this skill's own measurements — see
[references/measurements.md](references/measurements.md).
