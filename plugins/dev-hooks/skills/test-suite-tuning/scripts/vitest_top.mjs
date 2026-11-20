// Slowest tests and files from a Vitest JSON report (Jest's --json has the same shape).
//   vitest run --reporter=default --reporter=json --outputFile.json=run.json
//   node vitest_top.mjs run.json [N=25] [--timeout MS=5000]
// Top-N share: the share of summed per-test time taken by the N slowest tests.
// Longest file: a runner that splits by file cannot finish a parallel run sooner than this.
// Near the timeout: tests over half of MS (the runner's testTimeout) fail first on a busy machine.
import { readFileSync } from "node:fs";

const args = process.argv.slice(2);
const at = args.indexOf("--timeout");
const timeout = at < 0 ? 5000 : Number(args.splice(at, 2)[1]);
const [path, count = "25"] = args;
if (!path || !(timeout > 0)) {
  console.error("usage: node vitest_top.mjs REPORT.json [N] [--timeout MS]");
  process.exit(2);
}
const n = Number(count);
const root = `${process.cwd()}/`;
const tests = [];
const files = [];
for (const f of JSON.parse(readFileSync(path, "utf8")).testResults ?? []) {
  const name = f.name.replace(root, "");
  let sum = 0;
  for (const t of f.assertionResults ?? []) {
    if (t.duration == null) continue; // skipped or todo
    const ms = t.duration;
    tests.push({ ms, name: `${name} > ${t.fullName ?? t.title}` });
    sum += ms;
  }
  files.push({ name, sum, count: (f.assertionResults ?? []).filter((t) => t.duration != null).length });
}
if (!tests.length) {
  console.error(`${path}: no test results (is it a --reporter=json report?)`);
  process.exit(1);
}
const total = tests.reduce((a, t) => a + t.ms, 0) || 1;
const pct = (ms) => `${((100 * ms) / total).toFixed(1)} %`;
const pad = (ms) => String(Math.round(ms)).padStart(7);
const secs = (ms) => `${(ms / 1000).toFixed(1)} s`;
tests.sort((a, b) => b.ms - a.ms);
files.sort((a, b) => b.sum - a.sum);
const top = tests.slice(0, n);
const topSum = top.reduce((a, t) => a + t.ms, 0);
const median = tests[tests.length >> 1].ms;
const near = tests.filter((t) => t.ms > timeout / 2);

console.log(`tests: ${tests.length}, files: ${files.length}, summed test time: ${secs(total)}`);
console.log(`top ${top.length} tests: ${secs(topSum)} = ${pct(topSum)} of summed test time`);
console.log(`longest file: ${secs(files[0].sum)} of tests (${files[0].name}): the floor of a parallel run`);
console.log(`median test: ${median.toFixed(1)} ms, over 1 s: ${tests.filter((t) => t.ms > 1000).length}, ` +
  `over 300 ms: ${tests.filter((t) => t.ms > 300).length}`);
console.log(`over half the ${timeout} ms timeout: ${near.length}`);
for (const t of near) console.log(`${pad(t.ms)}  ${t.name}`);
console.log(`\nslowest tests (ms):`);
for (const t of top) console.log(`${pad(t.ms)}  ${t.name}`);
console.log(`\nslowest files (summed test ms, share, tests):`);
for (const f of files.slice(0, 15)) console.log(`${pad(f.sum)}  ${pct(f.sum).padStart(7)}  ${String(f.count).padStart(4)}  ${f.name}`);
