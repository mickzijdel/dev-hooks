# Speed

Measure first. On a suite that already runs fast, the profile is the deliverable: it tells the
person there is nothing worth changing, and that saves a pass of edits.

Measure unit/integration tests and system/E2E tests as separate suites: they have different
costs and different fixes. In a worktree with its own database, run through `mise exec -- t`
(or the repo's equivalent): an agent's shell does not load `mise.local.toml`, so without it the
tests use the main checkout's database.

## Measure

1. **Spread.** Run each suite 3 times parallel and 3 times serial. The spread between runs is
   the smallest difference you can claim. Use the spread of the mode you will compare in (a
   serial change against the serial spread). Note the machine load (`uptime`) with each run:
   other work on the same machine moves the numbers, and a load jump makes a run worthless.
   Rails with `t`: `t` sets `PARALLEL_WORKERS`, which overrides `parallelize(workers: N)`, so a
   system suite that runs serially on CI may run in parallel locally. Time the CI command too if
   it differs.
2. **Boot.** `time RAILS_ENV=test bin/rails runner nil`, 3 times. More than 3 s: look at
   Bootsnap, initializers, gems loaded with no `require: false`.
   TypeScript: the time before the first test runs (`vitest run` on one tiny test file).
3. **Where the time goes.** Vitest prints it in every run: `Duration 41s (transform 30%, import
   40%, worker 10%, tests 20%)`. High transform or import means the suite spends its time
   compiling and loading modules, not testing. Jest: `--verbose` plus `--logHeapUsage`.
   Rails: one serial run with
   `RUBYOPT="-r$SKILL/scripts/event_share.rb" MAX_WORKERS=1 t`. It prints each event's total
   seconds and share of the run. Controller time includes its SQL and renders; the rest is Ruby
   in tests and models. In a system suite most of the time is the browser, which it cannot see:
   the shares there add up to far below 100 %.
4. **Slowest tests.** `--profile 25` (Minitest, RSpec), `--durations=25` (pytest),
   `--reporter=verbose` (Vitest) or `--verbose` (Jest), `reportSlowTests` (Playwright). Note what
   share of the run the top 25 make: under ~15 %, no single test is worth chasing. In a system
   suite the first test in each process also pays browser and server start (about 2 s): do not
   read that as the test being slow.
5. **Cheap global settings, read not run:** password hashing cost in test (Devise
   `config.stretches = Rails.env.test? ? 1 : 12`, `BCrypt::Engine.cost`), real `sleep` in app
   code on a test path (`rg -n '\bsleep\b' app lib test`), network calls without WebMock,
   truncation in place of transactions. TypeScript: a jsdom environment for tests that need no
   DOM, real timers where fake ones would do, a real network or database where a mock would do.
   System tests: asset builds triggered by the test run (Vite `autoBuild`, `cssbundling` in
   `test:prepare`), negated Capybara queries (`assert_not has_text?` waits the full timeout;
   use `assert_no_text`).

## Act on

| Profile says | Change |
|---|---|
| SQL over ~40 % | Factory cascades (TestProf `FPROF=1` for FactoryBot), `let_it_be`/`before_all` for shared setup, fixtures over factories for read-only data. |
| Controller time over ~30 % | Look for the actions with the most time (`--profile` on request tests) and for renders inside it: a page that renders hundreds of partials, or a layout that queries on every request. Often nothing to change: request tests are meant to run controllers. |
| One test type dominates | Push repeated system tests down to request or component tests; keep one system test per user journey. |
| A few slow tests, and the top 25 are over ~15 % | Read them. Usual causes: a real `sleep` or retry delay, a big file upload, an email rendered many times, a framework loaded lazily on first use. Stub the delay value (a constant, a Stimulus `data-*-delay-value`), not `sleep` itself. |
| Even spread, nothing over ~30 % | Nothing to do. Say so. |
| Parallel speedup far below the worker count | Rails hands out tests one at a time, so the split is rarely the cause: it is database or CPU contention, or a busy machine. Try fewer workers and measure. parallel_tests and Vitest split by file: there, split the slowest file. |
| Vitest/Jest: transform + import over ~50 % | Barrel files (`index.ts` that re-exports a whole package) pulled into every test; import the module directly. Set `environment: "node"` for tests that need no DOM. Check `isolate: false` / `pool: "threads"` with three runs before and after. |
| Playwright: one spec dominates | Log in once with `storageState` instead of in each test; set up data through the API, not the UI; keep UI steps for the journey under test. |

## Keep a change only if

Three runs after it are faster than three runs before it by more than the spread from step 1,
at a similar machine load. A change that touches JS or CSS triggers an asset rebuild: run once
to absorb it before the "after" runs. Record both sets in the commit message.

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
  57 s suite is below what three runs can show.
