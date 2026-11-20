# StrykerJS (TypeScript and JavaScript)

Run on StrykerJS 10.1 with the Vitest runner, Vitest 4.1, pnpm, a Next.js monorepo (Nov 2026).
The Jest and Mocha runners take the same options and were not run. Stryker runs locally and
sends nothing anywhere.

## What it does to the repo

- It copies the whole repo into `.stryker-tmp/sandbox-*` for every run and mutates the copy.
  Your working files are not changed (unless you set `inPlace`).
- It calls the runner's API with the repo's real runner config. It does **not** run your `test`
  script: whatever the script adds (environment variables, a `--config`) is missing unless you
  put it in the environment or in Stryker's `vitest.configFile`.
- It leaves `reports/`, `stryker.config.json`, and, after a crashed run, the full sandbox
  (hundreds of MB after a few crashes). Delete `.stryker-tmp/` after a crash.

## Install

Stryker is a dev dependency: a change to `package.json` and the lockfile, which a scoped task
may not commit. To try it without adopting it:

1. Install with the repo's package manager, picked by its lockfile (`pnpm add -D`,
   `yarn add -D`, `npm i -D`; `npm i` in a pnpm repo writes a second lockfile and rebuilds
   `node_modules`): `@stryker-mutator/core` and `@stryker-mutator/vitest-runner` (or
   `jest-runner`, `mocha-runner`). Use the machine's supply-chain wrapper if it has one
   (`sfw pnpm add …`); if it has none, check that the repo has its own release-age or trust
   policy (`minimumReleaseAge` in `pnpm-workspace.yaml`, `.npmrc`) and ask the person when
   there is neither.
2. Put `stryker.config.json`, `reports/` and `.stryker-tmp/` in `.git/info/exclude`.
3. While it is installed, stage files by name, never `git add -u` or `-A`.
4. At the end: copy the reports you need out of the repo, restore `package.json` and the
   lockfile from `HEAD`, reinstall, delete `reports/`, `.stryker-tmp/` and the two config
   files. `git status --short` must be empty apart from your test changes.

## Config

`stryker.config.json`:

```json
{
  "testRunner": "vitest",
  "plugins": ["@stryker-mutator/vitest-runner"],
  "concurrency": 6,
  "mutate": ["src/**/*.ts", "!src/**/*.test.ts", "!src/**/*.spec.ts"],
  "reporters": ["json", "progress"],
  "coverageAnalysis": "perTest",
  "ignorePatterns": ["e2e", "docs", "android", "ios"]
}
```

- `plugins`: needed with pnpm, which hides the runner from Stryker's auto-discovery; harmless
  elsewhere.
- `concurrency`: the default is cores − 1, each one a full runner. On a machine you share, use
  about a third of the cores: a starved runner turns kills into `Timeout`.
- `reporters`: `clear-text` prints a diff per survivor, thousands of lines for one file. Read
  the JSON report with `scripts/stryker_survivors.mjs` instead.
- `ignorePatterns`: folders the tests do not need. They are not copied, which is what makes a
  run start fast in a monorepo. Everything the runner config imports must stay.
- If the runner config sets `retry`, add `"vitest": { "configFile": "vitest.stryker.config.ts" }`
  and make that file import the repo's config and set `retry` to 0. Stryker does not switch
  retries off, so every kill runs twice. Runner options are config keys only: there is no
  `--vitest.configFile` flag. (Cheap to do; the saving was not measurable on a busy machine.)

## Commands

```bash
npx stryker run --dryRunOnly --mutate src/billing/invoice.ts --testFiles 'src/billing/__tests__/*.test.ts'
npx stryker run --mutate src/billing/invoice.ts --testFiles 'src/billing/__tests__/*.test.ts'
node $SKILL/scripts/stryker_survivors.mjs                       # one line per mutant not killed
# prune: a run that records every killer, the candidates, and a copy (the next run overwrites the report)
npx stryker run --disableBail --mutate … --testFiles …  && node $SKILL/scripts/kill_matrix.mjs --tests 'invoice\.test'
cp reports/mutation/mutation.json /tmp/before.json
# … delete or merge tests, run Stryker again with the same flags, then:
node $SKILL/scripts/stryker_survivors.mjs --killed-diff /tmp/before.json reports/mutation/mutation.json
```

- **`--testFiles` is part of the command.** Without it the Vitest runner runs every test file
  whose imports reach the mutated file, directly or through a router or a barrel: in an app
  with one root router that is most of the suite, each of them must pass inside the sandbox,
  and one unrelated failure aborts the run. Name the test files that are meant to test the
  file, and put them in the report: a survivor survived *those* tests.
- **`--dryRunOnly` first**: it proves the setup in one cheap run.
- **`--disableBail` for pruning.** Without it Stryker stops at the first failing test, so each
  mutant lists one killer and every other test looks like it kills nothing. `kill_matrix.mjs`
  warns when it sees that. On pure-function tests it cost nothing measurable.
- **`--incremental`** reuses earlier results for unchanged code and tests (file
  `reports/stryker-incremental.json`). It reran exactly the mutants covered by changed tests
  (114 of 153 reused after three test edits). It also reuses the one-killer results of an
  earlier bailed run, even with `--disableBail`: add `--force` to the prune run, or delete the
  file. Not worth it for a run that takes under a minute.

Never compare two Stryker wall times taken at different loads. Cost, with 6 runners: 153 mutants of a pure module with 27 node tests, 7 s. 313 mutants with
tests that render React in jsdom, 46 to 62 s. Minutes to hours means the test set is too wide.

## Start-up failures

| Error | Cause | Fix |
|---|---|---|
| `ts.parseConfigFileTextToJson is not a function` | Stryker rewrites `tsconfig.json` with the classic TypeScript API, which TypeScript 7 (the native port) does not have | `"tsconfigFile": "<a name that does not exist>"`. The real `tsconfig.json` is still copied unchanged, which is right when it has no `extends` or `references` that leave the repo. |
| `ENOTSUP … copyfile` | A committed symlink to a folder in the sandbox copy | Add its parent to `ignorePatterns`. |
| `Cannot find TestRunner plugin "vitest"` | pnpm's layout | The `plugins` line above. |
| `Something went wrong in the initial test run`, naming a test file you did not expect | No `--testFiles`, or a test that reads a folder you ignored | `--testFiles`; or take the folder out of `ignorePatterns`. |

## Reading the report

- Statuses: `Killed`; `Timeout` (counts as killed, but records no killer, so the kill matrix
  cannot credit a test for it; on a busy machine timeouts are starved runners, 8 of 280 kills
  in one run: rerun at a lower `concurrency` before you read them); `Survived`; `NoCoverage` (no test runs that line); `Ignored` /
  `Pending` (not run); `CompileError` / `RuntimeError` (invalid mutant, skipped).
- **Static mutants** (`"static": true`: a mutant in code that runs when the module loads, such
  as a constant table, a regex or a default object) were reported `Survived` whatever the tests
  did: 13 of 13 on a month-name table, of which 7 failed existing tests when applied by hand.
  Both scripts count them. Do not sort them as survivors: run with `--ignoreStatic` (they
  become `Ignored`, and the score is honest: 93.3 % against 89.5 %), and apply each one with
  `hand_bug.py`.
- The TypeScript checker (`"checkers": ["typescript"]`) is rarely worth it: Vitest, and Jest with
  SWC or esbuild, do not type-check, so a type-invalid mutant runs like any other and is killed
  or not on behaviour (0 compile errors in 466 mutants). It needs the classic TypeScript API too.
