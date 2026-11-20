// One line per mutant that was not killed, from a mutation-testing-report-schema JSON
// (StrykerJS, Stryker.NET, Stryker4s). The clear-text reporter prints a diff per survivor:
// thousands of lines for one file. This is the list to sort from.
//   node stryker_survivors.mjs [reports/mutation/mutation.json] [Survived,NoCoverage,...]
//   node stryker_survivors.mjs --killed-diff BEFORE.json AFTER.json
// --killed-diff lists the mutants killed in one report and not in the other: after a prune or a
// merge, "lost" must be empty. Counts can match while a mutant was swapped.
import { readFileSync } from "node:fs";

const KILLED = ["Killed", "Timeout"];
const load = (path) => JSON.parse(readFileSync(path, "utf8"));
const args = process.argv.slice(2);

function describe(file, f, m) {
  const lines = (f.source ?? "").split("\n");
  const { start, end } = m.location;
  const first = lines[start.line - 1] ?? "";
  const original = start.line === end.line
    ? first.slice(start.column - 1, end.column - 1)
    : `${first.slice(start.column - 1)} …`;
  const short = (s, n) => s.replace(/\s+/g, " ").trim().slice(0, n);
  return `${file}:${start.line}:${start.column} #${m.id} ${m.mutatorName}: ` +
    `\`${short(original, 70)}\` -> \`${short(m.replacement ?? "", 60)}\``;
}

function killedIn(report) {
  const out = new Map();
  for (const [file, f] of Object.entries(report.files))
    for (const m of f.mutants)
      if (KILLED.includes(m.status)) out.set(`${file}:${m.id}`, describe(file, f, m));
  return out;
}

if (args[0] === "--killed-diff") {
  if (args.length !== 3) {
    console.error("usage: node stryker_survivors.mjs --killed-diff BEFORE.json AFTER.json");
    process.exit(2);
  }
  const [before, after] = [killedIn(load(args[1])), killedIn(load(args[2]))];
  const lost = [...before].filter(([k]) => !after.has(k));
  const gained = [...after].filter(([k]) => !before.has(k));
  console.log(`killed before: ${before.size}, after: ${after.size}, lost: ${lost.length}, gained: ${gained.length}`);
  for (const [, d] of lost) console.log(`  lost    ${d}`);
  for (const [, d] of gained) console.log(`  gained  ${d}`);
  process.exit(lost.length ? 1 : 0);
}

const report = load(args[0] ?? "reports/mutation/mutation.json");
const want = (args[1] ?? "Survived,NoCoverage,RuntimeError,CompileError").split(",");
for (const [file, f] of Object.entries(report.files)) {
  const counts = {};
  for (const m of f.mutants) counts[m.status] = (counts[m.status] ?? 0) + 1;
  const total = f.mutants.length;
  const killed = KILLED.reduce((a, s) => a + (counts[s] ?? 0), 0);
  const valid = total - (counts.CompileError ?? 0) - (counts.RuntimeError ?? 0) - (counts.Ignored ?? 0);
  console.log(`${file}: ${total} mutants, ` +
    Object.entries(counts).map(([s, n]) => `${s} ${n}`).join(", ") +
    `, score ${valid ? ((100 * killed) / valid).toFixed(1) : "0.0"} %`);
  const statics = f.mutants.filter((m) => m.static);
  if (statics.length)
    console.log(`  static (code that runs at module load; status not reliable, check by hand): ` +
      `${statics.length}, of which ${statics.filter((m) => m.status === "Survived").length} Survived`);
  const listed = f.mutants.filter((m) => want.includes(m.status)).sort((a, b) =>
    a.location.start.line - b.location.start.line || a.location.start.column - b.location.start.column);
  for (const m of listed)
    console.log(`  ${m.status}${m.static ? " (static)" : ""} ${describe(file, f, m)}` +
      `  covered by ${m.coveredBy?.length ?? 0} tests`);
}
const tests = Object.entries(report.testFiles ?? {});
if (tests.length)
  console.log(`\ntest set (a survivor survived these, not the whole suite): ` +
    tests.map(([file, f]) => `${file} (${f.tests.length})`).join(", "));
