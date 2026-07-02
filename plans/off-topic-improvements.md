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
