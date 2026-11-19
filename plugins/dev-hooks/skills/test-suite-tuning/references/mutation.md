# Mutation testing and pruning

A mutation tool makes one small change to the code (a "mutant": `>=` becomes `>`, a line is
deleted), runs the tests that cover it, and restores the code. A test failure **kills** the
mutant. A mutant that **survives** is a bug the suite would let through. The method below is the
same for every stack; only the tool differs.

## Tools

| Stack | Tool | Kill matrix | Note |
|---|---|---|---|
| TypeScript / JavaScript (Vitest, Jest, Mocha, Karma) | StrykerJS | `scripts/kill_matrix.mjs` | Apache-2.0, free. Best-supported tool here. |
| Minitest (Rails) | `scripts/mutate.rb` | Ruby snippet below | No gem. Prism (Ruby 3.4+) finds the mutation points. |
| RSpec / Minitest | `mutant` gem | its own report | Stronger operators. Free for open source only: ask before using it on a private repo. |
| Python (pytest) | `mutmut` | none | POSIX only. `mutmut results` gives each mutant's status, not its killers: find gaps with it, and prune only by the hand-applied-bug rule. |
| C#, Scala | Stryker.NET, Stryker4s | `scripts/kill_matrix.mjs` | Same report schema as StrykerJS (not tried). |

## StrykerJS (TypeScript)

Add it as a dev dependency (it runs locally and sends nothing anywhere; on Mick's machines install
through `sfw npm`):

```bash
sfw npm i -D @stryker-mutator/core @stryker-mutator/vitest-runner   # or jest-runner, mocha-runner
```

`stryker.config.json`:

```json
{
  "testRunner": "vitest",
  "mutate": ["src/**/*.ts", "!src/**/*.test.ts", "!src/**/*.spec.ts"],
  "reporters": ["json", "clear-text", "html"],
  "coverageAnalysis": "perTest"
}
```

```bash
npx stryker run --mutate src/billing/invoice.ts   # one high-value file first
npx stryker run --disableBail --mutate src/billing/invoice.ts && node $SKILL/scripts/kill_matrix.mjs
```

- `perTest` (the default) runs only the tests that cover each mutant, like `mutate.rb`.
- **Use `--disableBail` for pruning.** Without it Stryker stops at the first failing test, so
  each mutant lists one killer and every other test looks like it kills nothing. Measured on a
  3-test pilot (Nov 2026): without the flag, each killed mutant listed exactly one killer.
  `kill_matrix.mjs` warns when it sees that.
- `--incremental` reuses earlier results for unchanged code and tests (file
  `reports/stryker-incremental.json`): useful for repeat runs on gaps, wrong for pruning. It
  reuses the one-killer results of an earlier bailed run, even with `--disableBail` (measured:
  "11 of 11 mutant result(s) are reused"). Add `--force` to the prune run, or leave incremental
  off. Add `reports/` to `.gitignore`.
- Statuses: `Killed`, `Timeout` (counts as killed, but records no killer, so the kill matrix
  cannot credit a test for it), `Survived`, `Ignored` / `Pending` (not run), `NoCoverage` (no test runs that
  line: a gap with no test at all), `CompileError` / `RuntimeError` (invalid mutant, skipped).
  Turn on `"checkers": ["typescript"]` (package `@stryker-mutator/typescript-checker`) if many
  mutants are type errors.

## mutate.rb (Minitest)

What it changes:

- comparisons and arithmetic: `==`/`!=`, `>`/`<=`, `<`/`>=`, `+`/`-`
- boundaries: `>=`→`>`, `>`→`>=`, `<=`→`<`, `<`→`<=`
- predicates and finders: `present?`/`blank?`, `any?`/`none?`, `exists?`→`none?`, `first`→`last`,
  `find_by`→`find_by!`
- logic: `&&`/`||`, `if`/`unless`, `true`/`false`
- statements: each call or `return` inside a method or a lambda (scope bodies) becomes `nil`
- declarations: each class-body call (`validates`, `belongs_to`, `scope`, `enum`, callbacks)
  becomes `nil`

It does not change integer or string literals, hash keys, arguments, or anything in
`db/schema.rb`. Those are its blind spots: see "Prune" below.

```bash
rm -rf tmp/pertest && RUBYOPT="-r$SKILL/scripts/per_test_coverage.rb" t
ruby $SKILL/scripts/mutate.rb app/models/x.rb --list
ruby $SKILL/scripts/mutate.rb app/models/x.rb --cov tmp/pertest --out tmp/kills_x.json
git diff --quiet app/models/x.rb || echo "x.rb is still mutated"
```

- Each mutant runs the tests whose coverage touches its line. A class-body line runs at load,
  when no test is active, so it runs every test that touches the file.
- It aborts if those tests are not green before mutating. It always records every killer, so
  it needs no `--disableBail`.
- Test names go to the run through `ONLY_TESTS_FILE` and `scripts/filter_tests.rb`, never on the
  command line: GNU `sem` (behind `t`) re-splits arguments in a shell, so a `-n /a|b/` filter
  breaks.
- Cost on a 130-line model with about 250 covering tests: 66 mutants in about 4 minutes, serial.
  Longer than the default Bash timeout: run it in the background.
- Record coverage again (with the `rm -rf`) after you add, rename or delete tests. A stale
  index shows as `partial` (fewer tests ran than asked) or as a "recorded twice" warning.
- A test from an included module or a base class is run through the file of the class that
  includes it.
- `--only i,j --out FILE` merges those results into FILE; without `--only`, FILE is replaced.
- Under SimpleCov, switch it off for the coverage run: a second `Coverage.start` raises.

Kill matrix from its output:

```ruby
require "json"; require "set"
file = "app/models/x.rb"
covering = Dir["tmp/pertest/cov-*.jsonl"].flat_map { File.readlines(_1) }.map { JSON.parse(_1) }
  .select { _1["cov"].key?(file) }.map { _1["test"] }.uniq
k = JSON.parse(File.read("tmp/kills_x.json"))["results"].select { _1["status"] == "killed" }
# a mutant that breaks most of a large suite says nothing; in a small suite it is still a kill
k.reject! { covering.size >= 10 && _1["killers"].size > covering.size / 2 }
kills = Hash.new { |h, t| h[t] = Set.new }
k.each { |m| m["killers"].each { |t| kills[t] << m["id"] } }
zero_kill = covering - kills.keys
# subsumed: another test kills a superset; of two equal tests, list only one
subsumed = kills.select { |t, s| kills.any? { |o, os| o != t && s.subset?(os) && (s != os || o < t) } }.keys
```

## Sorting survivors

Mutation tools are mechanical: they generate and run mutants. Sorting the survivors is
judgement, and it is the part of the work that matters. Read the code at each survivor and put
it in one of these groups:

| Kind | Test | Action |
|---|---|---|
| Gap | A real input makes the mutant behave differently and no test has that input (`>=`→`>` survives because no test uses exactly 18). | Add one behaviour test. Rerun those mutants; they must be killed. |
| Equivalent | No input can tell the mutant apart (a nil guard before a comparison that is false for nil anyway; `first`→`last` where any element works; deleting a `destroy_all` that `dependent: :destroy` already does). | Write the reason. Do nothing. |
| Dead code | The mutant deletes code and nothing changes because something else does the same (an explicit scope that duplicates one `enum` already defines). | See "Dead code" below. |

When unsure between gap and equivalent, try to write the test. If you cannot make it fail
against the mutant, it is equivalent.

## Dead code

Every dead-code survivor is a finding. Handle it in this order:

1. **Search for the same pattern** in the whole codebase, not only the mutated file. One
   duplicate enum scope in a Rails app led to four more in another model.
2. **Log every hit** in the repo's `plans/off-topic-improvements.md` (or its backlog), with the
   mutant that showed it.
3. **Remove the obvious ones** in their own commit: a pure duplicate whose replacement you can
   show does the same (for example, compare the SQL of the enum scope with the removed scope),
   with no caller outside the repo, and with the full suite green afterwards. Remove the
   finished entry from the log.
4. **Only log** anything less clear: public API, code another service or a template might call
   by name, or code that looks unused but whose purpose you cannot name. Ask the person.

## Prune

A kill-matrix candidate is a question, not an answer. Measured on one model's test suite (about 60 tests, a private Rails app):

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

So for each candidate:

1. Name the bug it guards, as a concrete code change.
2. Apply that change by hand and run the other tests (not the candidate).
3. Another test fails: delete it. Otherwise keep it, and consider whether the tool needs that
   operator. A test that looks framework-only still gets this check, with a wrong declaration
   (or a wrong prop, route or config value) as the bug.
4. After the batch, rerun the full mutant list for the file. The killed count must not drop.

Merging is the same rule: two tests may become one only when the merged test still fails for
each bug that either failed for.
