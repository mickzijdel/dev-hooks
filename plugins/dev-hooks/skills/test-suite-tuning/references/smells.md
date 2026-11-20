# Smells

`test_smells.py` is a heuristic: it reads JS/TS with strings, comments and regex literals
blanked and brackets matched, Ruby and Python by indentation. Every hit is a candidate to read.

## Reading the output

The first line counts files, tests, parametrised blocks (`it.each`) and asserting helpers. A
count that drops between two runs means the scan saw less, not that the suite got better.

A call to a helper whose own body asserts (`expectApproximately`, `assert_valid_record`) counts
as an assertion; in JS/TS only when the helper is defined in the test's file or imported by it.

With `--list FILE` (the scope list) or `--only REGEX` (searched in the file path), only tests
in those files are reported, while helpers are still read from every root: pass the wide
roots, so that a scoped scan and a full scan agree. In Ruby and Python a helper counts by its
name anywhere under the roots, which can hide a "no assertion" hit when a common word is also
a helper's name.

The two lists to skim (mock-only, snapshot-only) are printed as counts per file when they
have more than 25 hits; `--all` prints every test. Measured on one repo of 25,900 tests: 834
mock-only hits.

## The lists

- **focused** (`.only`, `fit`, `fdescribe`, Minitest `focus`): the rest of the file never runs.
  Fix at once.
- **conditional skip** (`describe.skipIf`, `it.runIf`, a `skip` call inside a hook,
  `@pytest.mark.skipif`, `skip … unless`): tests that
  can pass by not running. Check that the condition is not something the lane always provides
  or always lacks (a mock server, a variable CI sets): a block that never runs on CI is
  dead, and one that always runs needs no condition.
- **no assertion**: the test passes whatever the code does. If it is a deliberate "does not
  throw" test, make that explicit (`expect(() => f()).not.toThrow()`, `assert_nothing_raised`).
- **tautology** (`expect(true).toBe(true)`): a placeholder. Delete it or write the test.
- **skipped or todo**: write it or delete it; a skip with no reason and no date is dead.
- **fixed sleep**, longest first, with the duration where it is a literal: replace it with a
  wait for the thing itself (a waiting matcher, fake timers, time travel).
  - A sleep before a negative assertion ("nothing was saved") has no thing to wait for. It
    needs a fake clock, switched on before the timer starts: the stack file has the calls.
  - Leave a sleep that is the scenario: latency inside a fake server, a slow consumer, a poll
    loop with its own exit.
  - A helper that sleeps a fixed time is listed once, with the number of tests that call
    it: fix the helper. A sleep in a test that uses fake timers is listed last, marked so.
- **asserts only on mocks**, **snapshot only**: skim, do not work through. A mock assertion is
  right when the behaviour is the call (a callback, an email sent). It is wrong when it only
  checks that the code calls its own helper, or when the test's name promises more than the
  call ("hands it over unchanged", with only a call count). A snapshot alone checks that
  nothing changed, not that it is right.

## Proving a rewrite

A rewritten test is a claim about a test (SKILL.md, "The two proofs"): give `hand_bug.py` the
bug the test's name describes and see it fail. For a negative test on a fake clock, the bug is
"the thing does happen": if the test still passes with the save moved in front of the debounce,
the clock was switched on too late.

## Measured (Nov 2026)

- Four suites of 900 to 12,500 tests: every "no assertion"
  and "tautology" hit read by hand was a test that checks nothing or only that nothing throws
  (10 and 4 on the largest suite: cache-clearing tests with no check, placeholders, end-to-end
  tests that only wait for an element).
- A Vitest scope of about 2,500 tests: 20 sleep hits, of which 14 waited to show that something
  does not happen and 4 burned more than a second each; 11 mock-only hits, 1 worth a change.
- 9 s for 27,900 tests on a busy laptop.
