// Prune candidates from a mutation-testing-report-schema JSON (StrykerJS; Stryker.NET and
// Stryker4s write the same schema).
//   node kill_matrix.mjs [--tests REGEX] [reports/mutation/mutation.json]
// --tests: judge only tests whose file path matches (the mutated file's own tests). A test file
// that covers the mutated file in passing has another subject, which this run did not mutate.
// Run Stryker with --disableBail (and without incremental, or with --force) first: by default it
// stops at the first failing test, so each mutant lists one killer and every other test looks
// like it kills nothing. Needs coverageAnalysis "perTest" (the default) for coveredBy.
import { readFileSync } from "node:fs";

const args = process.argv.slice(2);
const at = args.indexOf("--tests");
const own = at < 0 ? null : new RegExp(args.splice(at, 2)[1] ?? "");
if (own?.source === "(?:)") {
  console.error("--tests needs a regex on the test file path");
  process.exit(2);
}
const report = JSON.parse(readFileSync(args[0] ?? "reports/mutation/mutation.json", "utf8"));
const names = {};
const fileOf = {};
for (const [file, f] of Object.entries(report.testFiles ?? {}))
  for (const t of f.tests) {
    names[t.id] = `${file} > ${t.name}`;
    fileOf[t.id] = file;
  }

// mutant ids are only unique per file in some Stryker ports: key them by file
const mutants = Object.entries(report.files).flatMap(([file, f]) =>
  f.mutants.map((m) => ({ ...m, key: `${file}:${m.id}` })));
if (!mutants.some((m) => m.coveredBy)) {
  console.error('no mutant has coveredBy: rerun with coverageAnalysis "perTest"');
  process.exit(1);
}
const covering = new Set(mutants.flatMap((m) => m.coveredBy ?? []));
const killed = mutants.filter((m) => m.status === "Killed" && m.killedBy?.length);
const timeouts = mutants.filter((m) => m.status === "Timeout").length;
const statics = mutants.filter((m) => m.static).length;
if (killed.some((m) => (m.coveredBy?.length ?? 0) > 1) &&
    killed.every((m) => m.killedBy.length === 1 || (m.coveredBy?.length ?? 0) <= 1))
  console.error("warning: no mutant covered by several tests has more than one killer; was --disableBail set?");

const kills = new Map(); // test id -> Set of mutant keys
let broad = 0;
for (const m of killed) {
  const cov = m.coveredBy?.length ?? covering.size;
  // a mutant that breaks most of the tests covering it says little; in a small set it still counts
  if (cov >= 10 && m.killedBy.length > cov / 2) {
    broad += 1;
    continue;
  }
  for (const t of m.killedBy) (kills.get(t) ?? kills.set(t, new Set()).get(t)).add(m.key);
}
const judged = (t) => !own || own.test(fileOf[t] ?? "");
const subset = (a, b) => [...a].every((x) => b.has(x));
const label = (t) => names[t] ?? t;
const zeroKill = [...covering].filter((t) => !kills.has(t) && judged(t));
const subsumed = new Map(); // test id -> the one test that makes every kill of it
for (const [t, s] of kills) {
  if (!judged(t)) continue;
  const by = [...kills].find(([o, os]) => o !== t && subset(s, os) && (s.size !== os.size || o < t));
  if (by) subsumed.set(t, by[0]);
}
const killers = new Map(); // mutant key -> number of tests that kill it
for (const s of kills.values()) for (const k of s) killers.set(k, (killers.get(k) ?? 0) + 1);
const shared = [...kills].filter(([t, s]) =>
  judged(t) && !subsumed.has(t) && [...s].every((k) => killers.get(k) > 1));

console.log(`covering tests: ${covering.size}, mutants: ${mutants.length}, killed: ${killed.length}`);
if (timeouts)
  console.log(`timeouts: ${timeouts} (no killer recorded: a test whose only kill was one is listed below)`);
if (statics)
  console.log(`static mutants: ${statics} (in code that runs at module load: their status is not ` +
    "reliable and a test that only kills these is listed below; check them by hand)");
if (broad)
  console.log(`left out as broad: ${broad} killed mutants (covered by 10+ tests and killed by more than half)`);
const testFiles = new Set([...covering].map((t) => fileOf[t]));
const unjudged = [...covering].filter((t) => !judged(t)).length;
if (own)
  console.log(`not judged: ${unjudged} tests in files that do not match ${own}`);
else if (testFiles.size > 1)
  console.log(`tests from ${testFiles.size} files cover these mutants: a test whose own subject was ` +
    "not mutated cannot be judged here (pass --tests REGEX for the mutated file's own tests)");

console.log("\nkill no mutant (candidates, not a delete list):");
zeroKill.forEach((t) => console.log(`  ${label(t)}`));
console.log("\nevery kill also made by one other test (candidates, not a delete list):");
for (const [t, o] of subsumed)
  console.log(`  ${label(t)}\n      kills ${kills.get(t).size}; all also killed by: ${label(o)}`);
console.log("\nno unique kill, but no single test makes them all (weak candidates):");
shared.forEach(([t, s]) => console.log(`  ${label(t)}\n      kills ${s.size}`));
