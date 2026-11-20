# Mutation testing and pruning

A mutation tool makes one small change to the code (a "mutant": `>=` becomes `>`, a line is
deleted), runs the tests that cover it, and restores the code. A test failure **kills** the
mutant. A mutant that **survives** is a bug the suite would let through. The method below is the
same for every stack; only the tool differs.

## Tools

| Stack | Tool | Kill matrix | Read |
|---|---|---|---|
| TypeScript / JavaScript (Vitest, Jest, Mocha) | StrykerJS (Apache-2.0) | `scripts/kill_matrix.mjs` | [stryker.md](stryker.md) |
| Minitest (Rails) | `scripts/mutate.rb`, no gem | Ruby snippet | [mutate-rb.md](mutate-rb.md) |
| RSpec / Minitest | `mutant` gem | its own report | Stronger operators. Free for open source only: ask before using it on a private repo. |
| Python (pytest) | `mutmut` | none | [pytest.md](pytest.md) |
| C#, Scala | Stryker.NET, Stryker4s | `scripts/kill_matrix.mjs` | Same report schema as StrykerJS (not tried). |

## The test set decides the result

A mutant "survived" means it survived the tests that ran against it. Before the first run,
name the test files that are meant to test the mutated file, run the tool with those, and put
the list in the report. Tests that reach the file in passing (a page-level test of another
feature) are not its tests: they make the score look better and the prune list worse.

Time per run tells you whether the set is right. A pure module with its own unit tests takes
seconds; tests that render a UI take about a minute per 300 mutants. Minutes to hours means the
set is too wide.

## Sorting survivors

Mutation tools are mechanical: they generate and run mutants. Sorting the survivors is
judgement, and it is the part of the work that matters. Read the code at each survivor and put
it in one of these groups:

| Kind | Test | Action |
|---|---|---|
| Gap | A real input makes the mutant behave differently and no test has that input (`>=`→`>` survives because no test uses exactly 18). | Close it (below). Rerun those mutants; they must be killed. |
| Equivalent | No input can tell the mutant apart (a nil guard before a comparison that is false for nil anyway; `first`→`last` where any element works; deleting a `destroy_all` that `dependent: :destroy` already does). | Write the reason. Do nothing. |
| Equivalent: type guard | The mutant removes a check that the type checker needs and the run time does not (`x === null \|\|` in front of `!Number.isFinite(x)`). On a typed codebase this was a quarter to a half of the survivors. | Write "type guard". Do nothing. |
| Equivalent on this engine | The mutant differs by the language and not by the runtime (a sort comparator that returns 0 for "greater": V8 only tests `< 0`). | Write which engine, and how you checked. |
| Dead code | The mutant deletes code and nothing changes because something else does the same (an explicit scope that duplicates one `enum` already defines). | See "Dead code" below. |
| Not a survivor | The tool's status is wrong for this mutant (the tool file says which: static mutants in StrykerJS). | Apply it with `hand_bug.py` and sort by that result. |

When unsure between gap and equivalent, try to write the test. If you cannot make it fail
against the mutant, it is equivalent.

**Closing a gap.** Look for a test that already names the behaviour. If there is one, the gap
is a weak assertion (`toHaveLength(25)` where the ids matter) or a missing input (a "garbage
value" test without 0): strengthen or extend that test. Add a new test only for a behaviour no
test names. A new test beside the weak one makes the old one a prune candidate: that is a merge
you caused.

## Dead code

Every dead-code survivor is a finding. Handle it in this order:

1. **Search for the same pattern** in the whole codebase, not only the mutated file. One
   duplicate enum scope in a Rails app led to four more in another model.
2. **Log every hit**, with the mutant that showed it: in the report, and in the repo's backlog
   file if it has one (`plans/off-topic-improvements.md`). Do not create a backlog file in a
   repo that has none.
3. **Remove the obvious ones** in their own commit, when your scope includes application code:
   a pure duplicate whose replacement you can show does the same (for example, compare the SQL
   of the enum scope with the removed scope), with no caller outside the repo, and with the
   suite green afterwards. Remove the finished entry from the log.
4. **Only log** anything less clear: public API, code another service or a template might call
   by name, code whose purpose you cannot name, and an early-return guard that a later fallback
   happens to repeat (removing a readable guard is not an improvement). Ask the person.

## Prune

A kill-matrix candidate is a question, not an answer. Measured on one model's test suite (about
60 tests, a private Rails app):

- 15 tests killed nothing at first. All 15 tested declarations the first operator set skipped.
  After adding the declaration mutants, 7 still killed nothing:
  - 4 tested only Rails (association readers, enum predicates, `ArgumentError` on a bad enum
    value). A wrong `foreign_key` on either association failed 61 other tests. **Deleted.**
  - 1 pinned the enum's integer values, which are stored in the database. **Kept.**
  - 2 checked schema defaults. **Kept** (cheap, and no code mutator reaches the schema).
- 43 tests had kills that another test also made. One of them checked that a state-change
  method raises when the record is already in the target state. It was the **only** test of 92
  that failed when that method's guard was loosened to allow the target state too. A kill-subset
  rule would have deleted it.

And on a TypeScript module with 27 tests: of 9 candidates, 4 were the only test that failed for
their named bug, 1 was deleted and 1 merged.

So for each candidate:

1. Name the bug it guards, as a concrete code change. The kill matrix names the test that
   makes the same kills: read that one first.
2. Put the change in a bugs file and run `hand_bug.py` with the test files that could catch it.
   Running all of them, the candidate included, is the same evidence as "the others": read
   whether a test other than the candidate fails.
3. A test other than the candidate fails: deletable. No other test fails: keep it, and consider
   whether the tool needs that operator. A test that looks framework-only still gets this
   check, with a wrong declaration (or a wrong prop, route or config value) as the bug.
4. Before deleting, check the other test is a real stand-in: at the same level (a page-level
   test of another feature is not a stand-in for a unit test), and not one of the keeps below.
5. After the batch, rerun the mutants of the file and compare the killed mutants themselves
   with the run before (for a Stryker report: `stryker_survivors.mjs --killed-diff`). None may
   be lost. A deletion plus a new test can keep the count and swap a mutant. Put the
   before and after counts in the commit message.

Keep, and report as "deletable by the rule, kept because …":

- tests that pin stored data (enum integers, serialised formats, schema defaults): no code
  mutator reaches the database;
- tests the file says are a port, a spec example or a parity case with another system;
- tests whose only stand-in is in another feature's suite.

Merging is the same rule: two tests may become one only when the merged test still fails for
each bug that either failed for.
