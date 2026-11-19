// Prune candidates from a mutation-testing-report-schema JSON (StrykerJS; Stryker.NET and
// Stryker4s write the same schema).
//   node kill_matrix.mjs reports/mutation/mutation.json
// Run Stryker with --disableBail (and without incremental, or with --force) first: by default it
// stops at the first failing test, so each mutant lists one killer and every other test looks
// like it kills nothing. Needs coverageAnalysis "perTest" (the default) for coveredBy.
import { readFileSync } from "node:fs";

const report = JSON.parse(readFileSync(process.argv[2] ?? "reports/mutation/mutation.json", "utf8"));
const names = {};
for (const [file, f] of Object.entries(report.testFiles ?? {}))
  for (const t of f.tests) names[t.id] = `${file} > ${t.name}`;

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
if (killed.some((m) => (m.coveredBy?.length ?? 0) > 1) &&
    killed.every((m) => m.killedBy.length === 1 || (m.coveredBy?.length ?? 0) <= 1))
  console.error("warning: no mutant covered by several tests has more than one killer; was --disableBail set?");

const kills = new Map(); // test id -> Set of mutant keys
for (const m of killed) {
  const cov = m.coveredBy?.length ?? covering.size;
  // a mutant that breaks most of the tests covering it says little; in a small set it still counts
  if (cov >= 10 && m.killedBy.length > cov / 2) continue;
  for (const t of m.killedBy) (kills.get(t) ?? kills.set(t, new Set()).get(t)).add(m.key);
}
const subset = (a, b) => [...a].every((x) => b.has(x));
const zeroKill = [...covering].filter((t) => !kills.has(t));
const subsumed = [...kills].filter(([t, s]) =>
  [...kills].some(([o, os]) => o !== t && subset(s, os) && (s.size !== os.size || o < t)));

console.log(`covering tests: ${covering.size}, mutants: ${mutants.length}, killed: ${killed.length}` +
  (timeouts ? `, timeouts: ${timeouts} (no killer recorded; a test whose only kill was one is listed below)` : ""));
console.log("\nkill no mutant (candidates, not a delete list):");
zeroKill.forEach((t) => console.log(`  ${names[t] ?? t}`));
console.log("\nevery kill also made by another test (candidates, not a delete list):");
subsumed.forEach(([t]) => console.log(`  ${names[t] ?? t}`));
