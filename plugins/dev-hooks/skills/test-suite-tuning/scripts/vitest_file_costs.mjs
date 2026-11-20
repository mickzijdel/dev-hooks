// Per-file split of a Vitest run: environment, import (collect), setup and test time.
// Vitest's JSON report has per-test time only, so it cannot show a file that takes seconds to
// import and milliseconds to test. Two modes, one file:
//   record:  FILE_COSTS_OUT=costs.json vitest run --reporter=default --reporter=/abs/path/vitest_file_costs.mjs
//   report:  node vitest_file_costs.mjs costs.json
// Needs Vitest 3 or later (the reporter API with onTestModuleEnd).
import { readFileSync, realpathSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const PARTS = ["environment", "import", "setup", "tests"];

export default class FileCostsReporter {
  rows = [];
  onTestModuleEnd(mod) {
    const d = mod.diagnostic();
    let tests = 0;
    let count = 0;
    for (const t of mod.children.allTests()) {
      tests += t.diagnostic()?.duration ?? 0;
      count += 1;
    }
    this.rows.push({
      file: mod.relativeModuleId,
      project: mod.project.name ?? "",
      count,
      environment: d.environmentSetupDuration,
      import: d.collectDuration,
      setup: d.setupDuration,
      tests,
    });
  }
  onTestRunEnd() {
    writeFileSync(process.env.FILE_COSTS_OUT ?? "file-costs.json", JSON.stringify(this.rows));
  }
}

function report(path) {
  const rows = JSON.parse(readFileSync(path, "utf8"));
  if (!rows.length) {
    console.error(`${path}: no files recorded`);
    process.exit(1);
  }
  const sum = (list, k) => list.reduce((a, r) => a + (r[k] ?? 0), 0);
  const all = PARTS.reduce((a, k) => a + sum(rows, k), 0) || 1;
  const pad = (ms) => String(Math.round(ms)).padStart(7);
  console.log(`files: ${rows.length}, worker-seconds: ${(all / 1000).toFixed(1)}`);
  for (const k of PARTS)
    console.log(`  ${k.padEnd(12)}${(sum(rows, k) / 1000).toFixed(1).padStart(8)} s  ${((100 * sum(rows, k)) / all).toFixed(1).padStart(5)} %`);
  const projects = [...new Set(rows.map((r) => r.project))];
  if (projects.length > 1)
    for (const p of projects) {
      const rs = rows.filter((r) => r.project === p);
      console.log(`  project ${p || "(none)"}: files ${rs.length}, ` +
        PARTS.map((k) => `${k} ${(sum(rs, k) / 1000).toFixed(1)} s`).join(", "));
    }
  console.log("\nfiles by import time (import ms, test ms, tests):");
  for (const r of [...rows].sort((a, b) => b.import - a.import).slice(0, 15))
    console.log(`${pad(r.import)} ${pad(r.tests)} ${String(r.count).padStart(4)}  ${r.file}`);
  const heavy = rows.filter((r) => r.import > 1000 && r.import > 10 * r.tests);
  console.log(`\nfiles whose import is over 1 s and over 10x their test time: ${heavy.length}`);
  for (const r of heavy.sort((a, b) => b.import - a.import))
    console.log(`${pad(r.import)} ${pad(r.tests)} ${String(r.count).padStart(4)}  ${r.file}`);
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  if (!process.argv[2]) {
    console.error("usage: node vitest_file_costs.mjs COSTS.json   (see the header for the recording run)");
    process.exit(2);
  }
  report(process.argv[2]);
}
