# Flaky tests

A flaky test fails and passes on the same commit. The hard part is not the fix: it is finding
the flakes and then proving a fix worked.

## 1. Find them in CI history, not locally

Local repeats on a fast laptop find almost nothing. Measured (Nov 2026, two Rails apps): 16 full
runs of one suite and 5 of a 149-test system suite, with random seeds, gave zero failures. CI
history on the second app named two system tests that failed again and again on unrelated
commits.

```bash
mkdir -p tmp/ci   # must be gitignored (Rails apps ignore tmp/; check a JS repo): keep CI logs out of commits
gh run list --workflow CI --limit 300 --json databaseId,conclusion \
  | jq -r '[.[]|select(.conclusion=="failure")][0:25][].databaseId' \
  | while read id; do
      gh run view "$id" --log-failed > "tmp/ci/$id.log"
      rg -o -N '(Failure|Error):\s*$' -A1 "tmp/ci/$id.log" | rg -o '[A-Z][A-Za-z0-9:]+#test_\S+' | sort -u
    done | sort | uniq -c | sort -rn
```

That `rg` pattern matches Minitest output. For other runners, change the pattern:

- RSpec: `rspec ./spec/...` lines.
- Jest and Vitest: `●` lines (Jest) or `FAIL  path > name` lines (Vitest).
- pytest: `FAILED path::name` lines.
- Playwright with retries on: the report lists a test that failed and then passed on retry as
  **flaky**. Count those, not only the hard failures: in the summary, the names follow the
  `N flaky` line (`rg -A10 '^\s+\d+ flaky'`). A retry that hides a flake is still a flake.

A test that appears for two or more unrelated commits is a candidate. Skip failures in lint,
audit or Dependabot jobs.

Then read each failure message. The message says which kind of flake it is (table below), and
that matters more than reproducing it.

## 2. Reproduce, and measure a rate

1. Run the candidate's file 10 times (Playwright: `--repeat-each=10 --retries=0`). Then pin it to fewer cores, `taskset -c 0,1`, to imitate a
   slower CI runner, and run 10 more. Use growing batches (10, 20, 50) and record failures per
   batch.
2. For order dependence, use the failing seed from the CI log: `bin/rails test --seed N`, then
   `minitest_bisect --seed N test/**/*_test.rb` (gem `minitest-bisect`) or
   `rspec --seed N --bisect`. Vitest: `--sequence.shuffle --sequence.seed=N`; Jest:
   `--randomize --seed=N`. Neither has a bisect: halve the file list by hand.
3. For time dependence, run with a frozen clock at the CI run's time (`travel_to`,
   `vi.setSystemTime`, `jest.useFakeTimers().setSystemTime`), or with `TZ=UTC` and
   `TZ=Pacific/Auckland`.

Measured on the two system-test flakes above: 1 failure in 10 runs on 2 cores, 0 in 10 at full
speed, 0 in 20 on 1 core, and 0 in 20 on 2 cores with 2 CPU hogs. **1 in 70 is too rare to prove
a fix locally**: you would need 100 or more runs on each side to see a drop.

## 3. Fix, with proof

- With a measurable rate (at least 1 in 10): fix, then run the same batch under the same
  pinning. A fix counts when the rate goes to zero over at least 3× the runs it took to see a
  failure. Then remove each part of the fix in turn and rerun; keep only the parts that matter.
  Agent fixes tend to add sleeps and extra waits beside the one change that matters.
- With a rate too low to measure: fix the mechanism the error message names, say in the commit
  that the fix is unproven, and check CI history again after a few weeks. Do not loop CI jobs to
  measure: they cost Actions minutes.
- After three attempts that do not lower the rate: quarantine the test with an owner and an
  expiry, and report it. Never add a blanket retry, a fixed `sleep`, or a looser assertion.

## Kinds of flake, by message

| Message | Likely cause | Fix |
|---|---|---|
| `Node with given id does not belong to the document`, `StaleElementReferenceError` | Selenium kept an element that Turbo or a JS dialog replaced | Find the element again inside the assertion: assert on what the user sees after the action, with a waiting matcher (`assert_selector`, `assert_text`). Consider `Capybara.disable_animation = true`. |
| `expected to find text "..."` after a click on a JS dialog button | The click landed during the dialog's open animation, or before the Stimulus controller connected | Wait for the dialog's settled state, or disable animations in test; wait for the controller to connect before acting. |
| Passes alone, fails in the suite | State leak: class variables, `Rails.cache`, ENV, `I18n.locale`, `Current`, records outside the transaction | Bisect with the seed; reset the state in `teardown`. |
| Fails near midnight, month end or DST | Time | `travel_to`; never compare `Date.today` with a UTC timestamp. |
| Fails only under `parallelize` | Shared files, ports, Redis keys or a non-test DB | Make each worker's resource unique (`TEST_ENV_NUMBER`, the worker id). |
| Ordering of a list | A query with no `ORDER BY` | Add the order. Only when the order is not part of the behaviour, compare sorted lists. |
| `Timeout` in a Playwright test, `locator.click: element is not stable` / `intercepts pointer events` | An action raced a re-render, an animation or an overlay | Use web-first assertions (`await expect(locator).toBeVisible()`), never `page.waitForTimeout`. Wait for the network response the UI needs (`page.waitForResponse`). |
| Jest/Vitest: `act(...)` warning, or an assertion sees the old DOM | A state update after the test checked | `await findBy...` / `await waitFor(...)` in place of `getBy...` right after an action. |
| Passes alone, fails in the Jest/Vitest suite | Module state or a mock that leaks between tests | `restoreMocks: true` / `vi.restoreAllMocks()` in `afterEach`; reset module singletons; `vi.useRealTimers()` after fake timers. |
