# Flaky tests

A flaky test fails and passes on the same commit. The hard part is not the fix: it is finding
the flakes and then proving a fix worked.

## 1. Find them in CI history, not locally

Local repeats on a fast laptop find almost nothing. Measured (Nov 2026, two Rails apps): 16 full
runs of one suite and 5 of a 149-test system suite, with random seeds, gave zero failures, while
CI history on the second app named two system tests that failed again and again on unrelated
commits. On a busy laptop the opposite happens (third app): five tests failed at a load of 2 to
9 times the core count, and none of them appears in 346 CI runs.

```bash
gh workflow list                                    # use the name as printed; it is not always "CI"
bash $SKILL/scripts/ci_failures.sh -n 200 "<workflow name>"   # in the background: about a second per run
```

It reads check-run annotations, not logs: one small API call per run plus one per job, so
state the number before you start. It prints how many calls failed (a rate limit): the
counts are then a lower bound. With a scope, keep only the lines for tests in the scope
list. Read its output in this order:

1. **The date range.** `-n` is a number of runs, not a window: on a busy repo 400 runs is one
   day. Raise `-n` until the range covers two weeks or you reach 1,000 runs, whichever comes
   first, and put the range in the report.
2. **The table**: one line per annotated test, with the number of distinct head commits it
   failed at. Green runs and every attempt of a re-run job are read too, because where the
   runner retries, a flake almost never fails a run: its only record is a "passed on retry"
   annotation, which exists only where a reporter writes one.
3. **Failed or timed-out jobs with no test annotation.** That lane writes none (a runner config with a
   hand-written reporter list, a runner with no GitHub reporter), so its failures are only in
   the logs. The list gives one run id per job; `gh run list --workflow NAME --status failure`
   gives the rest. Fetch each failed run's log once, outside the repo, search it with the
   stack file's pattern, and count each test by distinct head commit:

   ```bash
   mkdir -p /tmp/ci
   gh run view "$id" --log-failed > /tmp/ci/$id.log   # the whole job: megabytes. Search it, never read it.
   ```

If the runner retries and nothing records a retried pass (no annotation, no log line), the
history is blind. Say so, and propose a retry reporter (a reporter that writes one line or
annotation per test that passed only on a retry) as the first finding; then go on with what
the failed runs show.

**A candidate** is a test that fails, or passes only on retry, at two or more unrelated head
commits. One failure on a pull-request or merge-queue branch may be the change under test. Skip
failures in lint, audit or dependency-update jobs.

**Before you work on a candidate**, compare its last failure date with `git log -3 -- <test
file>` and the code under it. A flake that stopped after a commit is already fixed: report it
as fixed, with the commit.

Then read each failure message. The message says which kind of flake it is (table below, and
the stack file's table), and that matters more than reproducing it.

## 2. Reproduce, and measure a rate

1. Run the candidate's file 10 times with retries off
   (`for i in $(seq 10); do <command> FILE > /tmp/rep-$i.log 2>&1 || echo "fail $i"; done`).
   Then slow it down to imitate a CI runner and run 10 more: `taskset -c 0,1 <command>` on
   Linux; on macOS, which has no `taskset`, `taskpolicy -b <command>` (background priority).
   Use growing batches (10, 20, 50) and record failures per batch, with the load: a failure
   that appears only when the load is above the core count is the machine (SKILL.md, Runs).
2. For order dependence, rerun with the failing run's seed, then bisect (stack file). A
   fixed-seed failure can still depend on speed: rerun it at low load before you name the cause.
3. For time dependence, run with a frozen clock at the CI run's time, or in another time zone.

Measured on the two system-test flakes above: 1 failure in 10 runs on 2 cores, 0 in 10 at full
speed, 0 in 20 on 1 core, and 0 in 20 on 2 cores with 2 CPU hogs. **1 in 70 is too rare to prove
a fix locally**: you would need 100 or more runs on each side to see a drop.

**Some flakes need a faster machine than yours**: two events inside one clock tick, a race that
a slow disk or a containerised database hides (measured: 3,000 local tries, 0 failures, for a
test that fails on CI). When the message points at one, do not chase a rate. Force the condition
by hand (the same timestamp, the same random value, the reversed order) and show the test fails
the same way as on CI. That forced failure is the "before"; the same forced run after the fix
is the "after".

## 3. Fix, with proof

- With a measurable rate (at least 1 in 10): fix, then run the same batch under the same
  slowing. A fix counts when the rate goes to zero over at least 3× the runs it took to see a
  failure. Then remove each part of the fix in turn and rerun; keep only the parts that matter.
  Agent fixes tend to add sleeps and extra waits beside the one change that matters.
- With a rate too low to measure: fix the mechanism the error message names, say in the commit
  that the fix is unproven, and check CI history again after a few weeks. Do not loop CI jobs to
  measure: they cost Actions minutes.
- An order dependence that only your shuffled runs show (CI may never shuffle) is still a
  defect in the tests: fix it when the fix stays inside the test file, otherwise report it.
- After three attempts that do not lower the rate: quarantine the test with an owner and an
  expiry, and report it.
- The rule against waits is about waiting for work to finish. A wait for the clock itself to
  move (to leave a millisecond or a second) is right when the test needs two different
  timestamps, and the test then asserts that they differ.

## Kinds of flake, by message

The stack file has the rows for your framework. These hold everywhere:

| Message | Likely cause | Fix |
|---|---|---|
| Fails near midnight, month end or DST | Time | Freeze the clock in the test; never compare a local date with a UTC timestamp. |
| Ordering of a list | A query with no `ORDER BY` | Add the order. Only when the order is not part of the behaviour, compare sorted lists. |
| Two rows or events "at the same time" | Two timestamps inside one clock tick | Assert on what must differ, and make the clock move between the two (see the last point of section 3). |
| A timeout on a test that takes seconds when the machine is quiet | The test is near its timeout and the runner was busy | Make the test do less (read the files once, not once per case). A longer timeout is a looser assertion. |
| Passes alone, fails in the suite | State that one test leaves for the next | Bisect with the seed (stack file); reset the state in teardown. |
