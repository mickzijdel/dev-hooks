# mutate.rb (Minitest)

No gem. Prism (Ruby 3.4+) finds the mutation points. Unlike StrykerJS it changes the real file
and restores it, so `git diff --quiet <file>` after a run is the check that matters.

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
`db/schema.rb`. Those are its blind spots: see "Prune" in mutation.md.

```bash
rm -rf tmp/pertest && RUBYOPT="-r$SKILL/scripts/per_test_coverage.rb" bin/rails test
ruby $SKILL/scripts/mutate.rb app/models/x.rb --list
ruby $SKILL/scripts/mutate.rb app/models/x.rb --cov tmp/pertest --out tmp/kills_x.json
git diff --quiet app/models/x.rb || echo "x.rb is still mutated"
```

- It runs the tests through the `t` test queue (rails.md) when that is on the PATH, else
  through `bin/rails test`;
  `--runner "CMD"` names another command.
- Each mutant runs the tests whose coverage touches its line. A class-body line runs at load,
  when no test is active, so it runs every test that touches the file.
- It aborts if those tests are not green before mutating. It always records every killer, so
  there is no bail to switch off.
- Test names go to the run through `ONLY_TESTS_FILE` and `scripts/filter_tests.rb`, never on the
  command line (rails.md says why, under the `t` queue).
- Cost on a 130-line model with about 250 covering tests: 66 mutants in about 4 minutes, serial.
  Longer than the default Bash timeout: run it in the background, one run per checkout.
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

`scripts/redundancy.rb` (per-test line coverage) is a weak hint only: on a suite of about 1,250
tests it called 1,051 tests "zero unique lines".
