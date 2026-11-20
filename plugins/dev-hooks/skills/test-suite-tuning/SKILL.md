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

## Before phase 1

**Stack.** This file says what to run. The stack file says how: the command for each need, and
what that runner gets wrong. Read yours now.

- [references/js.md](references/js.md): Vitest, Jest, Playwright
- [references/rails.md](references/rails.md): Minitest, RSpec
- [references/pytest.md](references/pytest.md)

**Scope.** Write three things down; every phase uses them, and the final report starts with them.

1. **The test files.** The whole suite, or, when the request names a part of the repo ("the
   billing tests"), a list in a file outside the repo, one repo-relative path per line: the
   tests beside that code, plus the tests elsewhere that import it or drive its pages (the
   stack file has a search). State the count. Every run and every script takes this same list
   (`-l`, `--list`; a tool that takes globs gets the same files). A timing of a part is not CI's timing: CI runs the whole suite.
2. **The lanes** that are in. A lane is a set of tests with its own command or config: unit,
   integration, system or end-to-end. Baseline and time each lane alone.
3. **What you may change.** Test files in the list: yes. Config that the whole repo shares (the
   runner config, a test helper, the CI workflow), application code, a new dependency, and tests
   outside the list: only when the person said so. Otherwise a finding or a fix that lies there
   goes in the report with its numbers and is not made; measure it with command-line flags where
   the runner has them.

**Runs.** Work in a worktree. Commit each phase that changes files on its own, so it can be
reverted alone.

- Start each suite run with `bash $SKILL/scripts/timed_run.sh [-l LIST] NAME <command>`, through
  the repo's own test script and, where the machine has one, its test queue (a wrapper that
  makes suite runs wait their turn). It prints wall time, exit code and the machine load, and
  keeps the output in `NAME.log`: give NAME a path outside the repo. One suite run at a time.
- **Retries off, in every run.** A retry turns a flake into a pass, and it doubles the cost of
  every failure you cause on purpose. Read the runner config for a retry setting first.
- When it prints `LOAD ABOVE CORES` (other sessions, a build), that wall time is void, and a
  failure in that run may be the machine: run it again later. A failure seen only in such runs
  is listed in the report, with the load, and fixed only when CI history shows the same test.
  If the machine never goes quiet, compare the summed per-test time from the runner's report,
  which load moves less, and say in the report that the wall times are void.
- A test that is red in every run is not flaky: report it, and fix it first if it is in scope.

## The two proofs

Every change in every phase is kept on one of these, and on nothing weaker.

- **A timing claim** needs three runs before and three after (two commits or two worktrees),
  taken in turn on a machine you share (before, after, before, …). The difference must be
  larger than the spread: the slowest minus the fastest run of one side.
- **A claim about a test** (it catches this bug; another test also catches it; this guard is
  tested) needs the bug applied by hand and a run that fails:
  `python3 -I $SKILL/scripts/hand_bug.py BUGS.json -- <test command> <test files>` applies each
  bug you describe (`[{"id": "B1", "bug": "in words", "file": "src/x.ts", "edits": [["find", "replace"]]}]`),
  prints the tests that fail and restores the file. The edit is temporary, so it is allowed
  whatever the scope. A new or rewritten test that you have not seen fail proves nothing.

Never make a test pass by making it able to detect less: a blanket retry, a wait for work to
finish (`sleep`), a looser assertion or a longer timeout.

## Order

Phase 1 always runs: every later phase compares against it, and none is measurable while an
earlier one is red. Before phase 2, ask the person which of the others they want; a suite of
1,000 fast, stable tests may need only 4, 5 and 6. The phases run one after another on one
branch, never in parallel sessions: phases 2, 3 and 4 meet in the same tests (a real wait
is a flake, a cost and a smell), and the earliest phase you run fixes it.

## 1. Baseline

The suite is deterministic and you know its time.

- Three runs with different seeds in random order, two parallel and one serial. Record wall
  time, test count, failures and seed per run. The parallel time is the one people wait for; the
  serial run finds order and shared-state failures and gives a profile without contention.
- The serial run also carries the stack's slowest-tests report. Note from it, where the stack
  file says the runner has them: the **top-25 share** (the share of summed per-test time that
  the 25 slowest tests take), the **longest file** (where the runner splits by file, a parallel
  run cannot be shorter than it), and the tests that take **over half the runner's timeout**
  (the next flakes on a busy machine).
- A test that fails in one run and passes in another, with no `LOAD ABOVE CORES` on the failing
  run, goes to phase 2 with its seed.

## 2. Flaky tests

Every test that can fail without a code change is fixed or quarantined.
Read [references/flaky.md](references/flaky.md) before you start. In short:

- **Look in CI history first.** A few local runs on a fast laptop find almost nothing.
  `scripts/ci_failures.sh` counts, per test, the commits at which CI recorded a failure or a
  pass on retry. The tests at two or more unrelated commits, with the date range the runs
  cover, are the work.
- **Reproduce, and measure a rate**, in growing batches at full speed and slowed down. When the
  message names a race that needs a faster machine than yours, force the condition by hand.
- **Prove each fix.** At a rate of 1 in 10, ten clean runs happen by chance one time in three:
  a fix counts when 3× the runs it took to see a failure all pass. With a rarer flake, fix the
  mechanism the error message names and say in the commit that it is unproven.
- After three failed fix attempts on one test, quarantine it (a skip whose message has the
  reason, an owner and an expiry date) and report it.

## 3. Speed

Only where the profile shows a cost worth removing.
Read [references/speed.md](references/speed.md). In short: measure where the time goes, and
change only what the profile names. Before you rewrite a slow test or file, or decide not to,
measure the most the rewrite could win: the suite without it against the suite with it. A
suite that is already fast and evenly spread has no speed work: say so and move on.

## 4. Smells

Tests that cannot fail or never run, found by a scan that takes seconds.
Read [references/smells.md](references/smells.md) for what to do with each list.

`python3 -I $SKILL/scripts/test_smells.py [--list LIST] ROOT...` on the folders that hold tests
(TypeScript/JavaScript, Ruby, Python; no dependencies). With a scope, pass the wide roots and
the scope list: helpers are still read from the roots. Every hit is a candidate to read, and
every rewrite is a claim about a test: prove it with `hand_bug.py`.

## 5. Gaps

### Behaviour inventory

Read [references/inventory.md](references/inventory.md). List the behaviours from the code
(entry points, guards, state changes, jobs), then match each to a test. Do refusals first: they
are mechanical. Where the app can list its own routes at run time, one table-driven refusal
test over that list replaces a test per route and cannot go stale. Take state changes from
mutation testing, not from reading.

### Mutation testing

Read [references/mutation.md](references/mutation.md), then the file for your tool
([stryker.md](references/stryker.md) for TypeScript/JavaScript,
[mutate-rb.md](references/mutate-rb.md) for Minitest). The tool is mechanical; your work is
step 3. The loop:

1. Pick a high-value file (domain logic, services with branching, money, permissions), not the
   whole codebase, and name the test files that are meant to test it. Unit and integration
   tests only.
2. Run the tool on that file with those tests, green first. Afterwards `git status --short`
   shows only what you expect: no mutated source file, no leftover sandbox.
3. Read every result that was not killed. A broken run (no tests ran, or fewer than asked): fix
   the setup before you trust anything else. No coverage: no test at all. Survived: sort into
   **gap**, **equivalent** or **dead code**, with the reason for each.
4. For each gap: when a test already names the behaviour, add the missing input or strengthen
   its assertion; add a new test only for a behaviour no test names. Rerun and show those
   mutants killed.
5. Dead code: search for the same pattern, log every hit, and remove only what your scope lets
   you change.

## 6. Prune

Last, with the kill matrix from phase 5 as evidence. Read "Prune" in
[references/mutation.md](references/mutation.md). In short:

- **Candidates** come from the kill matrix: tests that kill no mutant, or whose every kill
  another test also makes, among the mutated file's own tests.
- **A candidate is not evidence.** Generic mutation operators miss the bug many tests exist
  for. For each candidate, name the specific bug it guards ("the cancel method also accepts an
  already-cancelled order"), apply exactly that with `hand_bug.py`, and delete only if a test
  other than the candidate fails. This holds for tests that look framework-only too: for a
  Rails association test the bug is a wrong `foreign_key`; for a React prop test, a wrong prop
  name.
- **Keep** tests that pin stored data, and tests the file says are a port or a parity case,
  whatever the rule says; report them as "deletable by the rule, kept because …".
- After deleting or merging, rerun the mutants of the file. No mutant that was killed before
  may survive now: compare the killed mutants themselves, not the counts.

## Done when

- The report starts with the scope (files, lanes, what you could change) and gives, for each
  phase you ran, its before and after numbers (time, failure rate, mutation score, test count)
  with the machine load of the timed runs.
- Every commit passes the tests in scope, with retries off.
- Every new, rewritten, merged or deleted test has its `hand_bug.py` result in the commit
  message; a prune commit also has the killed-mutant counts before and after.
- Findings you could not act on inside the scope are listed with their numbers: shared config,
  application code, dead code, tests outside the list.
- Survivors, quarantined tests and dead code are listed for the person, each with a reason.
