# JavaScript and TypeScript: Vitest, Jest, Playwright

The Vitest commands were run on Vitest 4.1 in a Next.js monorepo with pnpm (Nov 2026). The Jest
and Playwright columns come from their documentation and were not run: check the first use.

## Running

- **Use the repo's own test script** (`package.json` scripts: `pnpm unit`, `npm test`) and put
  files and flags after it: `pnpm unit src/a.test.ts --retry=0`. A bare `vitest` skips the
  projects, setup files and environment that the script sets up. `npm` needs `--` before the
  flags (`npm test -- --retry=0`); a pnpm wrapper may want it or strip it.
- **Prove the flags arrived**: a seeded Vitest run prints `Running tests with seed "101"`.
- **A `--reporter` flag replaces the config's `reporters` list.** Name `default` beside any
  reporter you add, and any reporter of the repo's own that you rely on.
- **Read the runner config first** for `retry` (Vitest), `retries` (Playwright) or
  `jest.retryTimes`; for `testTimeout` (Vitest and Jest default: 5 s); for `projects` (node and
  jsdom tests cost differently: time them apart with `--project`); and for a hand-written
  `reporters` list, which drops Vitest's automatic `github-actions` reporter, so that lane
  writes no annotations.
- A path with parentheses (a Next.js route group) needs single quotes in zsh.

| Need | Vitest | Jest (not run) | Playwright (not run) |
|---|---|---|---|
| Seeded random order | `--sequence.shuffle --sequence.seed=N` | `--randomize --seed=N` | none: order is fixed per file |
| Serial | `--no-file-parallelism` | `--runInBand` | `--workers=1` |
| Retries off | `--retry=0` | remove `jest.retryTimes` | `--retries=0` |
| One file, one test | `FILE`, `FILE -t "name"` | the same | `FILE -g "name"` |
| One project | `--project NAME` | `--selectProjects NAME` | `--project=NAME` |
| Fewer workers | `--maxWorkers=2` | `--maxWorkers=2` | `--workers=2` |
| Repeat | a shell loop over the command | a shell loop | `--repeat-each=N --retries=0` |
| JSON report | `--reporter=default --reporter=json --outputFile.json=F` | `--json --outputFile=F` | `--reporter=json` |
| Slowest tests | `node $SKILL/scripts/vitest_top.mjs F [N] [--timeout MS]` | the same script | `reportSlowTests` in the config |
| Cost per file | `FILE_COSTS_OUT=C <test script> --reporter=default --reporter=$SKILL/scripts/vitest_file_costs.mjs`, then `node $SKILL/scripts/vitest_file_costs.mjs C` | none | none |
| Coverage | `--coverage --coverage.reporter=json --coverage.reportsDirectory=DIR` | `--coverage` | none |

**A scope list** for code in `src/server/billing` (paths as they are, no quotes; one list per
lane):

```bash
{ fd -e ts -e tsx '\.(test|spec)\.' src/server/billing; rg -l 'server/billing' -g '*.test.*' -g '*.spec.*' src; } | sort -u > /tmp/scope.txt
bash $SKILL/scripts/timed_run.sh -l /tmp/scope.txt /tmp/base1 pnpm unit --retry=0 --sequence.shuffle --sequence.seed=101
```

The `rg` finds direct imports only: read the list, and add end-to-end specs by the pages they
open. Do not pass the list through a shell variable: zsh hands an unquoted `$FILES` to the
runner as one argument, and Vitest answers `No test files found` in half a second. An
environment variable for a reporter goes in front: `FILE_COSTS_OUT=/tmp/c.json bash
$SKILL/scripts/timed_run.sh …`.

## Baseline

- `--sequence.shuffle` reorders the tests inside each file as well as the files.
- Vitest and Jest give every file a fresh worker that imports its module graph again. A serial
  run pays that one file after another (measured: 212 s serial wall for 152 s of tests and 32 s
  parallel), so its wall time says nothing about CI. Use it for order failures and for the
  slowest-tests report.
- `vitest_top.mjs` prints the three numbers phase 1 asks for. `--reporter=verbose` is no
  substitute: one unsorted line per test.

## Flaky

- **Failing tests in a GitHub log.** Vitest prints `FAIL  path > suite > name`, with colour
  codes inside the line, a `job<TAB>step<TAB>timestamp` prefix, and each failure twice:
  `sed -E 's/\x1b\[[0-9;]*m//g' LOG | rg -o 'FAIL .*\.(test|spec)\.[cm]?[jt]sx? > .*' | sort -u`.
  A bare `FAIL` also matches program output. Jest: `●` lines. Playwright with retries lists a
  test that failed and then passed as **flaky**: the names follow the `N flaky` line
  (`rg -A10 '^\s+\d+ flaky'`).
- **Order dependence.** No runner here has a bisect. Rerun only the failing file with the same
  seed first: Vitest shuffles inside the file, so the polluter is usually there, and
  `--reporter=verbose` prints it just above the failing test. Only when the file passes alone,
  halve the file list by hand.
- **Time.** `vi.setSystemTime`, `jest.useFakeTimers().setSystemTime`, or `TZ=UTC` and
  `TZ=Pacific/Auckland`.

| Message | Likely cause | Fix |
|---|---|---|
| `act(...)` warning, or an assertion sees the old DOM | A state update after the test checked | `await findBy...` / `await waitFor(...)` in place of `getBy...` right after an action. |
| Passes alone, fails in the suite | Module state or a mock that leaks between tests | `restoreMocks: true` / `vi.restoreAllMocks()` in `afterEach`; reset module singletons; `vi.useRealTimers()` after fake timers. |
| Passes alone, fails after another test in the same file | A real timer from the earlier test (a debounce, a toast, a poll) fires in this one | Cancel the timers the test started in `afterEach` (track them through a `setTimeout` spy), or fake the timer. `vi.clearAllTimers()` clears fake timers only. |
| Playwright `Timeout`, `element is not stable`, `intercepts pointer events` | An action raced a re-render, an animation or an overlay | Web-first assertions (`await expect(locator).toBeVisible()`), never `page.waitForTimeout`. Wait for the response the UI needs (`page.waitForResponse`). |

## Speed

- **Where the time goes.** Every Vitest run ends with `Duration 32.10s (transform 25.97s, setup
  6.51s, import 90.30s, tests 178.76s, environment 14.00s)`. The parts are worker-seconds summed
  over all workers, so they add up to far more than the wall time: divide each by their sum for
  its share (most of transform is inside import). `vitest_file_costs.mjs` gives the same split
  per file and per project, and lists the files that import for over a second and over 10× their
  test time. Jest: `--verbose` plus `--logHeapUsage`.
- **Boot.** The wall time of one run of the smallest test file: the fixed cost of every run.
- **Read, not run:** a jsdom environment for tests that need no DOM, real timers where fake ones
  would do, a real network or database where a fake would do.
- Under fake timers `performance.now()` and `Date.now()` are faked too, so a test cannot time
  itself: use the report's time.

| Profile says | Change |
|---|---|
| Import share over ~50 % | Barrel files (`index.ts` that re-exports a whole package) pulled into every test: import the module directly. `environment: "node"` for tests that need no DOM. Try `--no-isolate` and `--pool=threads`: they are flags, so a scoped run can measure them with no config change. |
| A file that imports for 10× its test time | Look at what its first import pulls in: a whole app, a barrel, a heavy client. Mock it or import narrower. |
| The longest file is close to the parallel wall time | That file is the run. Split it, or shorten its waits; measure the upper bound first (speed.md). |
| Tests that wait out a real debounce or retry delay | A fake clock, as in Smells below. |
| Playwright: one spec dominates | Log in once with `storageState`; set up data through the API, not the UI; keep UI steps for the journey under test. |

## Smells

A sleep before a negative assertion ("no save after the debounce") becomes, in Vitest:

```ts
vi.useFakeTimers({ shouldAdvanceTime: true }); // before the action that starts the timer
await user.type(input, "x");
await act(() => vi.advanceTimersByTimeAsync(1200));
expect(save).not.toHaveBeenCalled();
```

Three traps when moving a test to a fake clock:

- Restore mocks before real timers in `afterEach` (`vi.restoreAllMocks()`, then
  `vi.useRealTimers()`). With a spy on `setTimeout`, the other order puts the fake timer
  back, and every later test in the file that uses a real timer hangs for its full timeout.
- A test that mixes real I/O with fake timers cannot advance until done: the clock runs ahead
  of the I/O. Fake only what you need (`toFake: ["setTimeout", "clearTimeout", "Date"]`), wait
  on `setImmediate` until the code has asked for the timer, then advance by exactly that timer.
- A time read from the real clock just before the switch differs from the fake clock's start
  by 0 to 1 ms: do not assert an exact elapsed time across the switch.

Repeats do not find a race in a rewritten timing test: have a reviewer subagent read it.

`shouldAdvanceTime` keeps Testing Library's `waitFor` and user-event working. A timer created
before the switch runs on the real clock, and the test then passes whatever the code does. So
the hand-applied bug for this rewrite is "the thing does happen": the same advance must make a
test of the positive case see it.

## Inventory

Where the behaviours are:

| Source | Where to look |
|---|---|
| Entry points | Next.js `app/**/page.tsx`, `route.ts` and server actions (`"use server"`); `middleware.ts` and `next.config` rewrites; Express, Fastify or Hono routers; tRPC procedures; MCP tools; CLI commands |
| Who may do what | middleware, an auth check in each handler, route guards, a gate call in each `page.tsx` |
| State changes | reducers, state machines, status fields |
| Work off the request | queues, cron routes (each `vercel.json` cron needs a secret check), webhooks, durable workflows |

Two traps in a Next.js app. A guard in a `layout.tsx` does not protect the pages under it: each
`page.tsx` needs its own gate and its own test. And a catch-all `route.ts` can mount a whole
framework app (Hono, Express): the file list shows one route where there are hundreds, so list
that app's routes too.

**Matching routes to tests.** There is no recorder for this stack: nothing here watches which
route each test reaches and whether it was refused, as `route_hits.rb` does for Rails. What
you have instead:

- *Never refused* needs no matching at all when the app can list its routes (Hono
  `app.routes`, Express `app._router.stack`, tRPC `_def.procedures`): write the one
  table-driven refusal test from inventory.md.
- *Never reached*: run the scope with coverage and read which handler functions have a zero
  count in `coverage-final.json` (its `f` and `fnMap` per file). That is a run, so tables,
  constants and imports cannot fool it. It does not say who called the handler, or whether the
  call was refused.
- A string search for each path in the tests (`rg -l "'/api/orders'"`) is a first list only,
  wrong in both directions (measured: it called 133 of 191 routes untested). Table-driven tests (`describe.each(ROUTES)`) reach routes whose
  path appears in no test. Client tests that fake the server (`routes["PUT /api/views/5"] =`)
  name a path and never call the server. Paths built from constants match no literal. And a
  guard on the next line of a wrapped declaration is missed by a line search: read the whole
  call.

## Mutation

StrykerJS: [stryker.md](stryker.md). Not for Playwright suites (too slow per mutant).
