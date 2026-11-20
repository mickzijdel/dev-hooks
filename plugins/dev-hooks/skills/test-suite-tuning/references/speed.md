# Speed

Measure first. On a suite that already runs fast, the profile is the deliverable: it tells the
person there is nothing worth changing, and that saves a pass of edits.

Measure each lane (unit/integration, system/E2E) as its own suite: they have different costs
and different fixes. The commands for each step are in the stack file.

## Measure

1. **Spread.** Three runs of each lane with one seed, in the mode you will compare in (parallel,
   unless the change is about the serial profile), each through `timed_run.sh`. The baseline
   runs do not count: their seeds differ, and order moves the time. The spread (slowest minus
   fastest) is the smallest difference you can claim. Where other sessions share the machine,
   also record a number that load moves less: the summed per-test time from the runner's
   report.
2. **Boot**: the time before the first test runs.
3. **Where the time goes**: the split of the run into its parts (loading code, setup, database,
   rendering, the tests themselves). Per file where the runner splits by file.
4. **Slowest tests**, with the three numbers from phase 1. Top-25 share under ~15 %: no single
   test is worth chasing for the summed time. But in a runner that splits by file (Vitest, Jest,
   `parallel_tests`), a parallel run cannot be shorter than its longest file, whatever that
   file's share: compare the longest file with the parallel wall time.
5. **Cheap global settings**, read, not run: the stack file's list.

## Act on

The stack file's table maps a profile to a change. Two rows hold everywhere:

| Profile says | Change |
|---|---|
| A few slow tests, and the top 25 are over ~15 % | Read them. Usual causes: a real `sleep` or retry delay, a big file upload, an email rendered many times, a framework loaded lazily on first use. |
| Even spread, nothing over ~30 %, longest file far below the parallel wall time | Nothing to do. Say so. |

## Measure the most a change could win

Before you rewrite a slow test or split a slow file, and before you decide it is not worth it,
run the suite without it against the suite with it: three runs each way, in turn. No code is
written for this: "without" is the file list with that file taken out.

- Inside the spread: stop. No version of the rewrite can be shown to help.
- Outside it: that difference is the budget of the rewrite.

Measured (Nov 2026, a Vitest suite of 145 files): the slowest file was 11 % of summed test time
and 5 % of worker-seconds, and it waited on real retry delays. With it the parallel run took
30.9 / 32.6 / 37.7 s; without it 19.2 / 19.0 / 18.9 s. The share said "cannot matter"; the file
was the longest one, so it was the run.

## Keep a change only if

Three runs after it are faster than three runs before it by more than the spread from step 1,
interleaved, with no `LOAD ABOVE CORES` run on either side. Record both sets, with their loads,
in the commit message.

## Measured (Nov 2026)

A private Rails 8 app, Minitest, about 1,250 tests, Postgres, 6 workers:

- 11 s parallel, 31–36 s serial, boot 0.65 s, Devise stretches already 1.
- Event share: controller actions 26 %, SQL 14 %, jobs 8 %, renders 6 %. Nothing to change.
- Silencing the debug log (53 MB per run): 31.3 / 31.8 s with it, 34.0 / 31.4 s without. No
  effect.

BlackLightning (open-source Rails 8 app), 3,934 unit/integration and 149 system tests:

- Unit: 42–49 s parallel, 94–98 s serial (spread ±3.5 / ±2.4 s); boot about 1 s. Event share:
  controller 35 %, SQL 21 %, partials 14 %, templates 9 %. Top 25 tests: 11 % of the run.
- System: 20.5–22 s parallel, 56–57 s serial (spread ±0.8 / ±0.4 s). Event share covers only
  about 20 %; the rest is browser round trips. Top 25 tests: 37 % of the run.
- Replacing a `sleep 1.5` in the slowest-but-two system test with a zero Stimulus delay: no
  difference against the spread (57.9 / 56.4 / 57.9 s after). Reverted. One test's sleep in a
  serial 57 s suite is below what three runs can show.

A private Next.js app, Vitest 4, 145 test files in scope (2,690 tests), 18 cores, other sessions
on the machine:

- 32–46 s parallel at a load of 5 to 46; 212 and 260 s serial for 152 s of tests.
- Worker-seconds: tests 57 %, import 29 %, environment 4 %, setup 2 %. Top 25 tests: 28 % of
  summed test time.
- The one change worth making was the longest file (above).
