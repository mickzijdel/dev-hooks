---
name: test-suite-tuning
description: Use to improve an existing test suite rather than write new tests: "prune the tests", "remove useless/redundant tests", "merge tests", "find missing tests", "what isn't tested", "speed up the test suite", "the tests are slow", "fix flaky tests", "this test fails randomly on CI", "audit test quality", or mutation testing (Stryker, mutant, mutmut). TypeScript/JavaScript (Vitest, Jest, Playwright), Rails (Minitest) and pytest. Not for test-first work on new code (test-driven-development).
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Agent
  - Edit
  - Write
---

# test-suite-tuning

Make an existing suite **find more bugs, run faster and fail only when something is wrong**,
with a measured result for every change. Opinion about a test ("it looks redundant") is never
enough: each phase below names the signal that decides, and the signal comes from a run.

`$SKILL` below is this skill's folder (the folder that holds this SKILL.md); use its absolute
path in commands.

Work in a worktree. Run every suite through the repo's queue if it has one (`t` for Ruby apps on
Mick's machines). Commit one phase at a time, so each can be reverted alone.

## Commands by stack

| Need | Vitest | Jest | Playwright | Minitest (Rails) | pytest |
|---|---|---|---|---|---|
| Seeded random order | `vitest run --sequence.shuffle --sequence.seed=N` | `jest --randomize --seed=N` | (order is fixed per file) | `SEED=N t` | `pytest -p randomly --randomly-seed=N` |
| Serial | `--no-file-parallelism` | `--runInBand` | `--workers=1` | `SEED=N MAX_WORKERS=1 t` | no `-n` |
| Slowest tests | `--reporter=verbose` (times per test) | `--verbose` | `reportSlowTests` in the config, or `--reporter=json` | `--profile 25` | `--durations=25` |
| Repeat one test | loop the command | loop the command | `--repeat-each=N --retries=0` | loop `t FILE` | `pytest --count=N` (plugin pytest-repeat) |
| Mutation | StrykerJS | StrykerJS | not useful (too slow) | `scripts/mutate.rb` | `mutmut` |

## Order

Run the phases in this order. A later phase is not measurable while an earlier one is red.

1. **Baseline** — the suite is deterministic and you know its time.
2. **Flaky** — every test that can fail without a code change is fixed or quarantined.
3. **Speed** — only where the profile shows a cost worth removing.
4. **Smells** — tests that cannot fail or never run, found by a fast scan.
5. **Gaps** — a behaviour inventory (what has no test, what is never refused), then mutation
   testing on the code that matters; one behaviour test per real gap.
6. **Prune** — last, with the kill matrix from phase 5 as evidence.

Ask the person which phases they want; a suite of 1,000 fast, stable tests may need only 4, 5 and 6.

## 1. Baseline

- Run the full suite 3 times with different seeds, twice parallel and once serial (table
  above). Record wall time, runs, failures and seed per run. With `t`, pass the seed as `SEED=`,
  not `--seed`: `t` treats a flag-only run as a single-file run with one worker.
- Run once serially with the slowest-tests option from the table.
- An inconsistent result here goes straight to phase 2 with its seed.

## 2. Flaky tests

Read [references/flaky.md](references/flaky.md) before you start. In short:

- **Look in CI history first.** A few local runs on a fast laptop find almost nothing. Failed CI
  runs whose failing test also fails on unrelated commits are the real list
  (`gh run view <id> --log-failed`, then collect the failing test names per run).
- **Reproduce slow, and measure a rate.** Pin the run to two cores (`taskset -c 0,1` on Linux) to imitate
  a CI runner, then repeat in growing batches (10, then 20, then 50).
- **Prove each fix.** With a rate of at least 1 in 10, a fix counts only when 3× the runs it
  took to see the failure rate (30 runs at 1 in 10), under the same pinning, all pass. Ten clean
  runs prove nothing: at 1 in 10 they happen by chance one time in three. Then remove each part
  of the fix in turn and rerun the same 30: a part matters if failures come back. With a rarer
  flake, fix the mechanism the error message names, say in the commit that it is unproven, and
  check CI history again later.
- Never add a blanket retry, a `sleep`, or a looser assertion to make a test pass. After three
  failed fix attempts on one test, quarantine it with an owner and an expiry and report it.

## 3. Speed

Read [references/speed.md](references/speed.md). In short: measure where the time goes before you
change anything (for Rails, `scripts/event_share.rb` gives each event's share of serial test
time with no new gem; for Vitest, its own duration summary splits transform, import, worker and
tests). Change only what the profile names, and
keep a change only if three runs before and three after show a difference larger than the run-to-
run spread. A suite that is already fast and evenly spread has no speed work: say so and move on.

## 4. Smells

`python3 -I $SKILL/scripts/test_smells.py test` (or `src`, `spec`, `e2e`: the folders that hold
tests). No dependencies; TypeScript/JavaScript, Ruby and Python; about a second on 12,000 tests.
It lists:

- **focused** (`.only`, `fit`, `fdescribe`, Minitest `focus`): the rest of the file never runs.
  Fix at once.
- **no assertion**: the test passes whatever the code does, unless it is a deliberate "does not
  throw" test (then make that explicit: `expect(() => f()).not.toThrow()`, `assert_nothing_raised`).
- **tautology** (`expect(true).toBe(true)`): a placeholder. Delete it or write the test.
- **skipped or todo**: write it or delete it; a skip with no reason and no date is dead.
- **fixed sleep**: replace with a wait for the thing itself (a waiting matcher, fake timers,
  `travel_to`). This overlaps with phase 2.
- **asserts only on mocks**, **snapshot only**: read each. A mock assertion is right when the
  behaviour is the call (a callback, an email sent); it is wrong when it only checks that the
  code calls its own helper. A snapshot alone checks that nothing changed, not that it is right.

It is a heuristic (regex plus brace and indent matching), and every hit is a candidate to read.
Calls to helpers whose own body asserts (`expectApproximately`, `assert_valid_record`), in the
test files or in support files under `test/`, `spec/` or `__tests__/`, count as assertions.
Measured (Nov 2026) on four suites of 900 to 12,500 tests: after fixes for Jasmine `expectAsync`,
RxJS `expectObservable`, `done()` callbacks, template literals and multi-line Python signatures,
every "no assertion" and "tautology" hit read by hand was a test that checks nothing or only that
nothing throws (10 and 4 on the largest suite: cache-clearing tests with no check, placeholders,
end-to-end tests that only wait for an element). The mock-only list is long and mostly fine
(`expect(onClose).toHaveBeenCalled()` is often the behaviour): skim it, do not work through it.

## 5. Gaps

### Behaviour inventory

Read [references/inventory.md](references/inventory.md). List the behaviours from the code
(routes, guards, state changes, jobs), then match each to a test. For Rails,
`scripts/route_hits.rb` lists the routes no test reaches and the routes no test sees refused.
Add a behaviour test per real gap and a refusal test per unguarded-looking route.

### Mutation testing

Read [references/mutation.md](references/mutation.md) for the tool of your stack (StrykerJS for
TypeScript, `scripts/mutate.rb` for Minitest, `mutmut` for pytest). The tool is mechanical; your
work is step 3. The loop:

1. Pick a high-value file (domain logic, services with branching, money, permissions), not the
   whole codebase. Unit and integration tests only: system and E2E tests are too slow.
2. Run the tool on that file, in the background (it takes minutes), one run per checkout. Its
   tests must be green first. Check afterwards that the file is not left mutated
   (`git diff --quiet <file>`).
3. Read every result. Killed or timeout: fine. Invalid or compile error: skipped. A broken run
   (no tests ran, or fewer than asked): fix the setup before you trust anything else. No
   coverage: a gap with no test at all. Survived: sort into **gap** (a behaviour no test checks),
   **equivalent** (the change cannot alter behaviour) or **dead code** (something else already
   does it). Write the reason for each.
4. For each gap, add one test that states the behaviour, then rerun those mutants and show them
   killed.
5. For dead code, follow "Dead code" in mutation.md: search the codebase for the same pattern,
   log every hit in `plans/off-topic-improvements.md`, remove the obvious duplicates in their
   own commit with the suite green, and only log anything unclear or public.

## 6. Prune

Read the prune section of [references/mutation.md](references/mutation.md). The rule that held up:

- **Candidates** come from the kill matrix (`scripts/kill_matrix.mjs` for Stryker reports, run
  with `--disableBail`; the Ruby snippet in mutation.md for `mutate.rb`): tests that kill no
  mutant in the files they cover, or whose kills another test also makes.
  `scripts/redundancy.rb` (per-test line coverage, Ruby) is a weak hint only: on a suite of about
  1,250 tests it called 1,051 tests "zero unique lines".
- **A candidate is not evidence.** Generic mutation operators miss the bug many tests exist for.
  For each candidate, name the specific bug it guards ("the cancel method also accepts an already-cancelled order"),
  apply exactly that change by hand, and run the other tests. Delete only if another test fails.
  This holds for tests that look framework-only too: for a Rails association test the bug is a
  wrong `foreign_key`; for a React prop test, a wrong prop name. Another test must catch it.
- Keep tests that pin stored data (enum integers, serialised formats, schema defaults) even with
  zero kills: a code mutator cannot reach the database.
- After deleting, rerun the full mutant list for the affected file. The killed count must not
  drop. Put both counts in the commit message.

## Done when

- Each phase you ran has its before and after numbers in the final report (time, failure rate,
  mutation score, test count).
- Every commit in the worktree passes the suite through the queue.
- Survivors, quarantined tests and dead code you found are listed for the person, each with a
  reason. Dead code is also in `plans/off-topic-improvements.md`, or removed in its own commit.

## What did not work (measured, Nov 2026)

- Silencing test logging on a Rails suite with a 53 MB test log: no measurable change.
- Removing a 1.5 s `sleep` from a 57 s serial system suite: not measurable against the spread.
- Local repeats of a system suite with two known CI flakes: 1 failure in 70 targeted runs, even
  pinned to fewer cores and with CPU hogs. Too rare to prove a fix locally.
- Deleting by kill-subset alone: would have removed the only test that catches a plausible bug.
