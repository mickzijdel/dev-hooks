# Off-topic improvements (noticed, out of scope)

Noticed 2026-07-02 while reviewing mattpocock/skills for vendoring:

- **Debugging feedback-loop material** (upstream `engineering/diagnosing-bugs`): the 10-way
  catalogue for constructing a repro loop (failing test, curl script, replay a captured trace,
  bisection harness, differential loop, …), "tighten the loop" (faster / sharper signal /
  deterministic), and raising the reproduction *rate* for flaky bugs instead of chasing a clean
  repro. No home yet — superpowers:systematic-debugging owns the trigger; revisit if that ever
  moves in-house.
- **Tagged debug prefixes** (`[DEBUG-a4f2]` on every temporary log so cleanup is one grep) —
  would pair well with the dev-hooks `debug-leftover-reminder` hook, e.g. the hook could
  suggest the convention in its reminder text.
- **Tautological-test anti-pattern** (assertion recomputes the expected value the same way the
  code does, so it passes by construction) — candidate for the missing-test-reminder text or a
  testing-guidance reference.
- **Vertical-slice / tracer-bullet framing** for breaking plans into independently-shippable
  issues (each slice cuts through all layers, demoable on its own) — useful language for
  plan-writing guidance.
- **adr skill has a dangling `[[agent-handoff]]` wikilink** (`plugins/thinking-tools/skills/adr/SKILL.md`)
  — either write that skill (upstream's 15-line `handoff` is a seed) or drop the link.
- **marketplace.json's thinking-tools description omits `adr`** (and now the three new skills);
  CLAUDE.md says descriptions stay stable, but if it's meant to enumerate skills it's drifting.

Noticed 2026-09-03 while shipping the prompt-log redaction:

- **hk's `gitleaks` step scans gitignored build artifacts.** A stale
  `tests/__pycache__/*.pyc` holding a *previous* version of a test fixture blocked a commit with
  a phantom finding that no longer existed in any tracked file. `gitleaks dir` walks the tree
  rather than reading only the staged blobs. Fix: scope the step with
  `gitleaks git --staged` (or add `--no-git`-safe excludes for `__pycache__`, `.venv`, `node_modules`)
  in `hk.pkl`, so a build artifact can never fail a commit.
- **`tests/test_hook_sunset_bets.py` classifies bets but never checks the reasoning behind a
  retire verdict.** Three weekly reviews argued `detect-stack-skills` should be deleted from fire
  counts alone, which cannot distinguish "redundant" from "working" (see
  `plans/automation-reviews/2026-09-03.md`). Candidate: have the weekly-automation-review skill
  require a mechanism probe — does the hook's advice point at anything that exists? — before any
  DELETE verdict, rather than a fire-count argument.
