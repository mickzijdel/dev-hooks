# Rails: Minitest, RSpec

The Ruby scripts were run on two Rails 8 apps with Minitest and Postgres (Nov 2026), through
the `t` queue below. The plain `bin/rails test` forms are Rails' documented ones; the RSpec
entries come from its documentation and were not run.

## Running

| Need | Minitest | RSpec (not run) |
|---|---|---|
| Seeded random order | `bin/rails test --seed N` (random by default) | `rspec --seed N` |
| Serial | `PARALLEL_WORKERS=1 bin/rails test` | no `parallel_tests` |
| Retries off | none by default; look for `minitest-retry` in the Gemfile | look for `rspec-retry` |
| One file, one test | `bin/rails test FILE`, `FILE:LINE` | `rspec FILE:LINE` |
| Repeat | a shell loop over the command | a shell loop |
| Slowest tests | `--profile 25` | `--profile 25` |
| Unit and system suites | `bin/rails test` and `bin/rails test:system`: two lanes | by folder |

`bin/rails test:system` takes the same environment variables; pass a seed as `TESTOPTS="--seed N"`
(Rails' documented form, not run here).

In a worktree with its own database, check which database the tests use before the first run
(`bin/rails runner -e test 'puts ActiveRecord::Base.connection_db_config.database'`): an
agent's shell may not load the worktree's environment file, and the tests then run against
the main checkout's database. Run through the tool that loads it (with mise:
`mise exec -- bin/rails test`).

**A scope list** is rarely needed (name the folder: `bin/rails test test/models/billing`).
When it is, `timed_run.sh -l LIST NAME bin/rails test` works as for any runner.

## Baseline

`--profile 25` prints the 25 slowest tests and no total. The top-25 share is their sum over the
serial run's `Finished in` time. Rails hands out tests one at a time, so there is no longest
file to note (with `parallel_tests` there is: sum the profile per file). Minitest has no
per-test timeout; in a system suite, note the tests within reach of
`Capybara.default_max_wait_time` instead.

### With the `t` test queue

Some machines put a queue in front of every suite run (`t`: a wrapper that makes runs from
several checkouts wait their turn). Where it exists, every command above goes through it:

- Seed and workers are environment variables: `SEED=N t`, `SEED=N MAX_WORKERS=1 t`. A flag-only
  call (`t --seed N`) is read as a single-file run with one worker.
- `t` sets `PARALLEL_WORKERS`, which overrides `parallelize(workers: N)`: a system suite that
  runs serially on CI may run in parallel locally. Time the CI command too if it differs.
- `t` passes arguments through GNU `sem`, which splits them again in a shell: a
  `-n /a|b/` name filter breaks. The scripts here pass test names through a file for that
  reason.

## Flaky

- Minitest writes no GitHub annotations unless a reporter gem adds them, so expect
  `ci_failures.sh` to list the test job under "failed jobs with no test annotation" and use
  the logs.
- **Failing tests across the failed runs**, Minitest (RSpec: match the `rspec ./spec/...`
  lines instead). A test that appears in two or more runs at unrelated commits is a candidate:

  ```bash
  mkdir -p /tmp/ci
  gh run list --workflow "$WF" --status failure --limit 25 --json databaseId -q '.[].databaseId' |
    while read -r id; do
      gh run view "$id" --log-failed > "/tmp/ci/$id.log"
      rg -o -N '(Failure|Error):\s*$' -A1 "/tmp/ci/$id.log" | rg -o '[A-Z][A-Za-z0-9:]+#test_\w+[?!]?' | sort -u
    done | sort | uniq -c | sort -rn
  ```
- **Order dependence.** `bin/rails test --seed N` with the seed from the failing run, then
  `minitest_bisect --seed N test/**/*_test.rb` (gem `minitest-bisect`: a new dependency, so
  inside the scope only with a yes; without it, halve the file list by hand) or
  `rspec --seed N --bisect`.
- **Time.** `travel_to` the CI run's time.

| Message | Likely cause | Fix |
|---|---|---|
| `Node with given id does not belong to the document`, `StaleElementReferenceError` | Selenium kept an element that Turbo or a JS dialog replaced | Find the element again inside the assertion: assert on what the user sees after the action, with a waiting matcher (`assert_selector`, `assert_text`). Consider `Capybara.disable_animation = true`. |
| `expected to find text "..."` after a click on a JS dialog button | The click landed during the dialog's open animation, or before the Stimulus controller connected | Wait for the dialog's settled state, or disable animations in test; wait for the controller to connect before acting. |
| Passes alone, fails in the suite | State leak: class variables, `Rails.cache`, ENV, `I18n.locale`, `Current`, records outside the transaction | Bisect with the seed; reset the state in `teardown`. |
| Fails only under `parallelize` | Shared files, ports, Redis keys or a non-test DB | Make each worker's resource unique (`TEST_ENV_NUMBER`, the worker id). |
| Fails near midnight, month end or DST | Time | `travel_to`; never compare `Date.today` with a UTC timestamp. |

## Speed

- **Boot.** `time RAILS_ENV=test bin/rails runner nil`, 3 times. More than 3 s: look at
  Bootsnap, initializers, gems loaded with no `require: false`.
- **Where the time goes.** One serial run with
  `RUBYOPT="-r$SKILL/scripts/event_share.rb" PARALLEL_WORKERS=1 bin/rails test` (no new gem). It
  prints each event's total seconds and share of the run. Controller time includes its SQL and
  renders; the rest is Ruby in tests and models. In a system suite most of the time is the
  browser, which it cannot see: the shares there add up to far below 100 %, and the first test
  in each process also pays browser and server start (about 2 s).
- **Read, not run:** password hashing cost in test (Devise
  `config.stretches = Rails.env.test? ? 1 : 12`, `BCrypt::Engine.cost`), real `sleep` in app
  code on a test path (`rg -n '\bsleep\b' app lib test`), network calls without WebMock,
  truncation in place of transactions. System tests: asset builds triggered by the test run
  (Vite `autoBuild`, `cssbundling` in `test:prepare`), negated Capybara queries
  (`assert_not has_text?` waits the full timeout; use `assert_no_text`).
- A change that touches JS or CSS triggers an asset rebuild: run once to absorb it before the
  "after" runs.

| Profile says | Change |
|---|---|
| SQL over ~40 % | Factory cascades (TestProf `FPROF=1` for FactoryBot), `let_it_be`/`before_all` for shared setup, fixtures over factories for read-only data. |
| Controller time over ~30 % | Look for the actions with the most time (`--profile` on request tests) and for renders inside them: a page that renders hundreds of partials, or a layout that queries on every request. Often nothing to change: request tests are meant to run controllers. |
| One test type dominates | Push repeated system tests down to request or component tests; keep one system test per user journey. |
| Parallel speedup far below the worker count | Rails hands out tests one at a time, so the split is rarely the cause: it is database or CPU contention, or a busy machine. Try fewer workers and measure. `parallel_tests` splits by file: there, the longest file is the floor. |
| A slow test with a real `sleep` or retry delay | Stub the delay value (a constant, a Stimulus `data-*-delay-value`), not `sleep` itself. |

## Smells

A sleep before a negative assertion: `travel` past the delay inside the test
(`ActiveSupport::Testing::TimeHelpers`) for a time-based job or expiry; for a browser debounce in
a system test, set the delay value to zero in test and assert with `assert_no_text`, which
waits.

## Inventory

Where the behaviours are:

| Source | Where to look |
|---|---|
| Entry points | `bin/rails routes` |
| Who may do what | `before_action` guards, Pundit/ActionPolicy policies, `authenticate` blocks in routes |
| State changes | enum transitions, `!` methods that check a state |
| Work off the request | jobs, mailers, scheduled tasks |

`scripts/route_hits.rb` records which route each test reaches and whether it was refused:

```bash
rm -rf tmp/route_hits && RUBYOPT="-r$SKILL/scripts/route_hits.rb" bin/rails test
bin/rails runner $SKILL/scripts/route_hits.rb report
```

It lists routes no test reaches, and routes that tests reach but never see refused (no 401,
403 or 404, no halted `before_action`, no sign-in redirect from a routing constraint; a 422 from
an invalid form does not count). It needs forked test workers, not `parallelize(with:
:threads)`, and it leaves out engine routes, mounted Rack apps and `redirect()` routes.

Measured on a private Rails 8 app (Nov 2026, counting a 422 as a refusal, as an earlier version
did): 154 routes, 56 that no unit or integration test reached (most were Devise pages and admin
actions only system tests use) and 42 never refused, among them several admin actions whose
controllers each had their own guard and no non-admin test.

For the table-driven refusal test of inventory.md, the route list is
`Rails.application.routes.routes`.

## Mutation

`scripts/mutate.rb`, no gem: [mutate-rb.md](mutate-rb.md). The `mutant` gem has stronger
operators and is free for open source only: ask before using it on a private repo.
