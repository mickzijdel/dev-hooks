---
name: diagnosing-bugs
description: Use when the user says "diagnose"/"debug this", or reports something broken, throwing, failing, slow, or intermittent — especially bugs that resist a first glance. Triggers before hypothesising about a hard bug, a flaky failure, or a performance regression. Not for straightforward bugs with an obvious one-line fix.
---

# Diagnosing Bugs

A discipline for hard bugs — the ones that survive a first glance. Skip phases only when explicitly justified; the temptation to skip Phase 1 is exactly the failure mode this skill exists to prevent.

When exploring the codebase, read `CONTEXT.md` (if it exists) for the domain vocabulary and check nearby ADRs in `docs/decisions/` before forming theories.

## Phase 1 — Build a feedback loop

**This is the skill.** Everything else is mechanical. A **tight** pass/fail signal — one that goes red on *this* bug — turns bisection, hypothesis-testing, and instrumentation into a solved problem. Without one, no amount of staring at code will help.

Spend disproportionate effort here. Be aggressive, be creative, refuse to give up before you have one.

### Ways to construct one — roughly in this order

1. **Failing test** at whatever seam reaches the bug — unit, integration, e2e.
2. **Curl / HTTP script** against a running dev server.
3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot.
4. **Headless browser script** (Playwright/Puppeteer) — drives the UI, asserts on DOM/console/network.
5. **Replay a captured trace.** Save a real request/payload/event log to disk; replay it through the code path in isolation.
6. **Throwaway harness.** Spin up a minimal subset of the system (one service, mocked deps) that exercises the bug's code path with a single call.
7. **Property/fuzz loop.** If the symptom is "sometimes wrong output," run hundreds of random inputs and look for the failure mode.
8. **Bisection harness.** If the bug appeared between two known-good states (commit, dataset, version), automate "boot at state X, check, repeat" so it can run under `git bisect run`.
9. **Differential loop.** Run the same input through the old vs. new version (or two configs) and diff the outputs.
10. **HITL script.** Last resort, when a human must click something: drive *them* with [scripts/hitl-loop.template.sh](scripts/hitl-loop.template.sh) so the loop is still structured — captured answers feed back into the next phase.

### Tighten the loop

Once you have *a* loop, tighten it: can it run faster (cache setup, skip unrelated init, narrow scope)? Can the signal be sharper (assert on the specific symptom, not "didn't crash")? Can it be more deterministic (pin time, seed RNG, isolate filesystem, freeze network)? A 30-second flaky loop is barely better than none; a 2-second deterministic one is a debugging superpower.

### Non-deterministic bugs

The goal is a higher reproduction rate, not a clean repro. Loop the trigger 100×, parallelise, add stress, narrow timing windows, inject sleeps. A 50%-flake bug is debuggable; a 1% one is not — keep raising the rate until it is.

### When you genuinely cannot build a loop

Stop and say so explicitly. List what you tried. Ask for: (a) access to an environment that reproduces it, (b) a captured artifact (HAR file, log dump, core dump, timestamped recording), or (c) permission to add temporary instrumentation. Do not proceed to hypothesise without a loop.

### Completion criterion — a tight loop that goes red

Name **one command** — a script path, a test invocation, a curl — that you have **already run at least once** (paste the invocation and its output), and that is:

- [ ] **Red-capable** — drives the actual bug code path and asserts the exact symptom reported, so it goes red on this bug and green once fixed. Not "runs without erroring."
- [ ] **Deterministic** — same verdict every run (or, for flaky bugs, a pinned high reproduction rate).
- [ ] **Fast** — seconds, not minutes.
- [ ] **Agent-runnable** — unattended, except via the HITL script above.

If you catch yourself reading code to build a theory before this command exists, stop — that's the exact failure this skill prevents.

## Phase 2 — Reproduce + minimise

Run the loop. Confirm it produces the failure mode reported — not a different failure that happens to be nearby — and that it reproduces across multiple runs (or at a debuggable rate). Capture the exact symptom so later phases can verify the fix.

**Minimise:** shrink to the smallest scenario that still goes red. Cut inputs, callers, config, data, and steps one at a time, re-running the loop after each cut. Done when every remaining element is load-bearing — removing any one makes the loop go green. A minimal repro narrows Phase 3's hypothesis space and becomes the regression test in Phase 5.

## Phase 3 — Hypothesise

Generate 3–5 ranked hypotheses before testing any of them — a single hypothesis anchors on the first plausible idea. Each must be falsifiable: state its prediction ("if X is the cause, then changing Y makes the bug disappear / changing Z makes it worse"). If you can't state the prediction, the hypothesis is a vibe — discard or sharpen it.

Show the ranked list to the user before testing — they often have domain knowledge that instantly re-ranks it ("we just deployed a change to #3") or hypotheses they've already ruled out. Don't block on a response if they're unavailable; proceed with your own ranking.

## Phase 4 — Instrument

Each probe maps to a specific Phase 3 prediction. Change one variable at a time. Prefer a debugger/REPL breakpoint over logs when the environment supports it — one breakpoint beats ten logs. Never "log everything and grep." Tag every debug log with a unique prefix (`[DEBUG-a4f2]`) so cleanup is one grep.

For performance regressions, logs are usually the wrong tool: establish a baseline measurement (timing harness, profiler, query plan) and bisect against it instead. Measure first, fix second.

## Phase 5 — Fix + regression test

Write the regression test **before** the fix — but only if a correct seam exists for it. A correct seam exercises the real bug pattern as it occurs at the call site; a shallower one (a single-caller unit test when the bug needs multiple callers) gives false confidence.

If no correct seam exists, that itself is the finding — note it, the codebase's shape is preventing the bug from being locked down. [[codebase-design]] supplies the vocabulary for judging whether a new seam is warranted here.

With a seam: turn the minimised repro into a failing test, watch it fail, apply the fix, watch it pass, then re-run the Phase 1 loop against the original (un-minimised) scenario.

## Phase 6 — Cleanup + post-mortem

Required before declaring done:
- [ ] Original repro no longer reproduces (re-run the Phase 1 loop)
- [ ] Regression test passes (or the absent-seam finding is documented)
- [ ] All `[DEBUG-...]` instrumentation removed
- [ ] Throwaway prototypes deleted or clearly marked
- [ ] The hypothesis that turned out correct is stated in the commit/PR message, so the next debugger learns

Then ask: what would have prevented this bug? If the answer is architectural (no good test seam, tangled callers, hidden coupling), say so explicitly after the fix is in — you have more information now than when you started.
