# The standard (v18) — full specification

The detailed per-artifact requirements behind the summary in `../SKILL.md`. Read this before
writing or editing any of the standard's files. The version here tracks `../VERSION` (guarded
by the test suite).

## Required artifacts

A repo is **compliant at v18** when it has all of:

- **`mise.toml`** — `[tools]` pins `hk`, `pkl`, the stack tool (`uv` for Python), `gitleaks`,
  `zizmor` + `actionlint` (GitHub Actions security + correctness checks, added in v18), and (all stacks that run jscpd — Python,
  shell, Ruby/Rails, **and JS/TypeScript**) `node` (to run jscpd via `npx`; for JS it also serves
  as the stack tool); `[settings] lockfile = true` and `minimum_release_age = "4d"` (4-day
  supply-chain cooldown on `mise upgrade`; `mise install` always reproduces `mise.lock` exactly
  — see "Lockfile & supply-chain verification" in `../SKILL.md`); `[env]` carries the version
  stamp `DEV_ENV_VERSION = "18"`.
- **`mise.lock`** (committed) — records resolved tool versions + per-platform checksums so installs
  are reproducible and checksum-verified. See "Lockfile & supply-chain verification" in `../SKILL.md`.
- **`.jscpd.json`** (all stacks) — duplication config: `minTokens 70`, `threshold 0`,
  `reporters ["ai","threshold"]`, `gitignore true`, path excludes under `ignore` — the key must
  be `ignore`, **not** `ignorePattern` (inert for paths in jscpd v5; see the exclusions note)
  (vendored/generated dirs incl. `node_modules`, `vendor`, `dist`, `build`). The `missing-test-reminder` hook also reads this file to skip those dirs.
- **`scripts/run-jscpd.sh`** (all stacks, added in v14) — the shared jscpd runner, copied
  verbatim from `templates/run-jscpd.sh` (a repo's own hk fix step may re-indent it to local
  style — fine; never hand-edit the logic, the next policy change should be a plain re-copy). It is the **single home of the jscpd
  version-cooldown policy** (see the version-policy note below) and takes the stack's format
  list as its argument; the hk step runs `bash scripts/run-jscpd.sh <formats>` and CI's audit
  job runs the same with `--require` (offline + no cached jscpd then *fails* the job instead
  of warn-and-pass — pre-commit keeps warn-and-pass so a commit is never blocked by an
  unreachable registry).
- **`hk.pkl`** — amends a pinned hk `Config.pkl`, defines per-stack linter steps **plus the
  audits (dead-code + duplication), the `exec-bit-scripts` gate (v15), the `actionlint` + `zizmor`
  GitHub Actions checks (v18), `gitleaks`, and `check-added-large-files`** (`Builtins.*`),
  and wires `pre-commit` (`fix = true`, `stash = "git"`), `fix`, and `check` hooks. Every step —
  including the audits — lives in one `linters` mapping shared by all three hooks, so the audits
  **run on pre-commit** too (each is glob-gated, so a docs-only commit skips them); `check` is
  just the same set under one name that CI invokes. **Prefer an hk built-in** (`Builtins.<name>`)
  over a hand-rolled step whenever the built-in's command matches: `gitleaks`,
  `check_added_large_files`, `zizmor`, and `actionlint` are always built-ins (the `actionlint`
  one amended with `-shellcheck=`, below), and the shell stack uses
  `Builtins.ruff`/`Builtins.ruff_format` because there `ruff` is a mise tool (bare command on
  PATH). A stack that runs a tool through its package manager — `uv run ruff` (Python),
  `npx prettier` (JS), `bundle exec rubocop`/`bin/rubocop` (Ruby), `golangci-lint ./...` (Go) —
  keeps a **custom** step, because the bare-command built-in would resolve a different
  (or missing) binary and bypass the project-pinned version.
- **Executable-bit gate** (all stacks, added in v15) — the hk `exec-bit-scripts` step plus a
  mirroring step in CI's `lint` job fail when any git-tracked file whose **first line is a
  shebang** sits at index mode `100644`. A fresh clone or plugin-cache install receives the
  **index** mode, not local working-tree permissions — and with `core.fileMode = false` a local
  `chmod +x` never reaches git — so a 100644 script dies with exit 126 "Permission denied" on
  every other machine while working fine on the author's. Fix:
  `git update-index --chmod=+x <file>`. See "Executable bits on shipped scripts" below.
- **`.gitleaks.toml`** (all stacks) — a root allowlist file. The hk `gitleaks` step runs
  `gitleaks dir` over the **whole working tree** — `dir` has no respect-gitignore flag — so
  without this, any repo with a local `.env`, `log/`, `tmp/`, or a Rails
  `config/credentials/*.key` fails every commit and `hk run check` stays red, even though
  none of those are tracked. The file `[extend]`s the default ruleset and allowlists those
  gitignored runtime/secret **paths only** (source stays fully scanned). gitleaks auto-loads it
  from the scan root, so neither the hk builtin nor CI's `gitleaks git` needs a `--config`.
  See "gitleaks whole-tree allowlist" in `../SKILL.md`.
- **`.github/workflows/ci.yml`** — runs the same lint + test + gitleaks checks, plus an
  `audit` job (dead-code + duplication + a large-file guard), on push/PR. The `gitleaks` job
  runs the MIT-licensed gitleaks **CLI** via mise — `jdx/mise-action` +
  `mise exec -- gitleaks git --redact --no-banner .`, with `fetch-depth: 0` so the full commit history
  is scanned — **not** `gitleaks/gitleaks-action`, which requires a paid `GITLEAKS_LICENSE`
  on org-owned repos (the free tier covers exactly 1 repo per org; personal-account repos are
  unaffected, so the failure stays invisible until CI runs on an org repo). The CLI is free
  for every repo and is the same mise.lock-pinned binary the local hk hook runs.
- **SHA-pinned actions + read-only token** (all stacks, added in v16) — applies to **every file
  under `.github/workflows/`**, not just `ci.yml` (a repo's `deploy.yml`, `release.yml`, etc.
  count too). In each, every `uses:` pins a full commit SHA with the release tag in a trailing
  comment (`owner/repo@<sha> # vX.Y.Z`), and the workflow declares a top-level
  `permissions: { contents: read }` (a job needing more — a deploy needing `pages: write` /
  `id-token: write`, say — declares its own job-level block, or the workflow widens its own
  top-level block; never remove an existing wider block a deploy relies on). Tags are mutable,
  so an action-account takeover repoints `@v4` to malicious code that every downstream run picks
  up silently (tj-actions repointed 76 of 77 trivy-action tags to an infostealer); a SHA can't
  be moved, and a read-only default token contains the blast radius if a step is compromised.
  The checker enforces SHA-pinning across all workflow files (`has_sha_pinned_ci`);
  `scripts/check_action_refs.sh` scans the whole `.github/workflows/` dir and verifies each
  pin's comment resolves to the pinned commit on the remote. Bump pins with `pinact run -u`
  (it rewrites every workflow file). See "Keeping GitHub Actions current" in `../SKILL.md` and
  the **[[github-actions]]** skill's full security checklist.
- **GitHub Actions checks: actionlint + zizmor** (all stacks, added in v18) — hk steps
  (`Builtins.actionlint` + `Builtins.zizmor`) and a single CI `actions-lint` job run both over
  every workflow + `action.yml`, statically catching the workflow-level problems the SHA-pin rule
  doesn't. **actionlint** = *correctness*: schema/typo errors, invalid `${{ }}` expressions,
  undefined `needs:` (run as `actionlint -shellcheck=` so its shellcheck-of-`run:` pass doesn't
  duplicate the dedicated shellcheck step and trip on deliberately word-split commands).
  **zizmor** = *security*: credential persistence, `${{ … }}` template injection, over-broad
  `GITHUB_TOKEN` permissions, dangerous triggers; runs from the mise-pinned binary (so `mise.lock`
  checksum-verifies it) with offline audits only — no `GH_TOKEN` needed. Pairing zizmor: **every
  `actions/checkout` sets `persist-credentials: false`** (zizmor's `artipacked` finding) so the
  workflow's `GITHUB_TOKEN` isn't written into `.git/config` on the runner where a later step
  could exfiltrate it; a job that genuinely needs the persisted token (e.g. it pushes commits)
  keeps the default and adds a per-line `# zizmor: ignore[artipacked]`. The checker enforces both
  tools + hk steps (`has_zizmor`, `has_actionlint`). See the **[[github-actions]]**
  skill.
- **`README.md`** and **`CLAUDE.md`** (added in v3) — both present at the repo root, and both
  recording the **current versions of the project's key packages** (main framework, Tailwind,
  Bootstrap, etc.) so the human-facing docs don't drift from the manifests. The checker only
  enforces that both files exist; keeping the version numbers accurate is the writer's job (the
  `latest-deps-reminder` hook nudges Claude to update them on every manifest edit). If either
  doc is missing, the setup/upgrade flow **dispatches a subagent to create it** — see
  "Project docs (README + CLAUDE.md)" in `../SKILL.md`.
- **Dependency cooldown** (added in v6) — a Python repo pins a 4-day uv cooldown in
  `pyproject.toml` (`[tool.uv] exclude-newer`), so newly-published deps aren't resolved until
  they've been public long enough for a malicious release to be caught and yanked. The checker
  enforces this on Python stacks; Ruby and JS repos get the same window via their own package
  manager (recommended, not gated) — see "Dependency cooldown (supply-chain)" in `../SKILL.md`.

## Per-stack checks

See `templates/`. **When each runs:** every step — linters, large-file, and the dead-code +
duplication audits — runs on pre-commit (each glob-gated) and again in `check`/CI.

| Stack | Linters (pre-commit) | Tests | Secrets | Large file | Dead code (pre-commit) | Duplication (pre-commit) |
|-------|---------|-------|---------|------------|-----------|-------------|
| Python | `ruff check`, `ruff format` (via `uv run`) | `pytest` | gitleaks | `check-added-large-files` | `vulture` | `jscpd` |
| Ruby/Rails | `bin/rubocop` (omakase + rubocop-minitest\|-rspec; plain-rubocop adds rubocop-rails/-performance too), `herb` (ERB analyze + lint) | `bin/rails test` | gitleaks | `check-added-large-files` | `debride` | `jscpd` (polyglot gate) + `flay` (Ruby structural, advisory) |
| JS/TypeScript | `prettier` (check/fix) | — | gitleaks | `check-added-large-files` | — | `jscpd` (`-f javascript,typescript,css,scss`) |
| Go | `golangci-lint run` + `golangci-lint fmt` (gofmt/goimports), `shellcheck`/`shfmt` (shipped `.sh`) | `go test` (CI: `go build`/`go vet`/`go test -race`) | gitleaks | `check-added-large-files` | golangci-lint `unused` (built in) | `jscpd` (`-f golang`) |
| Shell / CC plugin | `shellcheck`, `shfmt`, `ruff` (any `.py`) | `pytest` over bundled scripts (see below) | gitleaks | `check-added-large-files` | `vulture` (any `.py`) | `jscpd` |

> Dead-code (`vulture`/`debride`) and duplication (`jscpd`/`flay`) run on pre-commit alongside the
> linters (each is glob-gated, so they only fire when a matching file is staged) and again in
> `check`/CI. They're fast enough warm — vulture ~0.15s, jscpd ~1s (cooldown resolve + scan) — and
> catching dead code / clones before push beats finding out in CI. Thresholds are tunable — see
> `upgrade-guide.md`.
>
> **jscpd** runs via `npx` (its v5 Rust engine — the `cpd` binary — ships through npm optional
> platform packages that `npx` resolves but the mise `npm:` backend doesn't), reading
> `.jscpd.json`. It uses the agent-friendly **`ai`** reporter (compact clone output) and the
> **`threshold`** reporter (CI gate). (Making it a real mise tool is deferred: `cargo:jscpd` works
> but needs a Rust toolchain per repo, and there are no prebuilt release binaries for an
> `aqua`/`ubi` backend — see `dropped-from-nate.md` for the tested comparison and
> revisit triggers, 2026-06-09.)
>
> **jscpd version policy (pre-commit + CI):** the gate neither pins a fixed version nor calls
> `@latest` blindly. Since v14 the whole policy lives in one place — `scripts/run-jscpd.sh` —
> which both the hk step and CI's audit job call, so the two can't drift. It tracks latest with
> a **4-day cooldown** — the same supply-chain seasoning as the dependency cooldowns (see
> "Dependency cooldown (supply-chain)" in `../SKILL.md`) — via `npx --before=<4 days ago>`, which
> resolves the newest release that has existed at least 4 days. It's **floored at v5** (the major
> `.jscpd.json` targets) so the cooldown can't regress to v4 while the v5 line is still <4 days
> old; if the cooldown pick is below the floor the script falls back to `latest`. It also
> **degrades gracefully offline**: when the registry is unreachable it runs the cached jscpd, and
> when nothing is cached it warns and passes rather than blocking the commit — unless invoked
> with `--require` (CI does), which fails instead. The cooldown resolve costs one registry
> round-trip (~0.9s) per commit that stages matching files.
>
> Configuring exclusions:
> - **Exclude paths** with `ignore` (a glob array) in `.jscpd.json`. **`ignorePattern` does NOT
>   exclude paths in jscpd v5** — it's silently inert there, which let CI scan the
>   CI-installed `vendor/bundle` gems and fail on their clones (seen in a Rails app, 2026-06-10;
>   fixed in v12). When testing exclusions, beware that jscpd loads `.jscpd.json` from the
>   **cwd**, not from the scanned directory — verifying against another path needs `-c <config>`,
>   otherwise you read the wrong config and conclude the wrong key works (how the original
>   "`ignore` has no effect" note happened). `gitignore: true` also skips gitignored paths, but
>   don't lean on it alone: CI-only dirs like `vendor/bundle` (created by `ruby/setup-ruby`
>   bundler-cache) are typically **not** gitignored, so the `ignore` globs must cover them.
> - **Restrict which file types are scanned** with `-f` on the command — there is no config
>   option for it, and without it jscpd also scans markdown/yaml/json and trips `threshold 0` on
>   README/CI/template duplication. Each stack passes the `-f` matching its glob: `-f python`
>   (Python), `-f python,bash` (shell/plugin), `-f ruby,erb,javascript,typescript,css,scss,sass,vue`
>   (Ruby), `-f javascript,typescript,css,scss` (JS/TypeScript), `-f golang` (Go). Add `ignore`
>   globs on top to skip
>   tracked code (e.g. generated `db/schema.rb`). For extensionless **PEP 723** scripts (e.g. `bin/foo`),
> jscpd keys off extensions, so duplication on extensionless scripts isn't auto-covered. To
> auto-fix clones, agents can run
> `npx skills add https://github.com/kucherenko/jscpd --skill dry-refactoring`.

> **Extensionless scripts (CC-plugin `bin/foo`, hooks) are linted by shebang — no glob
> surgery needed.** hk's `shellcheck`/`shfmt`/`ruff` builtins match by extension (`**/*.sh`,
> `**/*.py`), so they'd silently skip the extensionless executables plugin repos keep in
> `bin/`. The shell template (`hk.shell.pkl`) therefore carries companion steps —
> `shellcheck-scripts`, `shfmt-scripts`, `ruff-check-scripts`, `ruff-format-scripts` — that
> detect such files by **shebang on line 1 only** (`git ls-files | while read -r f; do head -n1
> "$f" | grep -qE '^#!.*…' && printf '%s\n' "$f"; done`), the same way the `vulture` step already
> does, and `ci.shell.yml` mirrors them. The `head -n1` matters: `grep -lE '^#!…'` would match a
> `#!` line **anywhere** in a file, so a `#!/bin/bash` inside a fenced code block in docs would be
> misdetected as a script and the linter would choke parsing prose as code — a shebang is only a
> shebang on line 1. They're **check-only**
> (a flagged script is fixed by hand or `ruff check --fix`/`shfmt -w`) and run full-tree.
> So you no longer hand-add extensionless CLIs to hk globs. `[tool.ruff] extend-include` is
> still worth setting (in `pyproject.toml`) to the **Python** extensionless scripts so a bare
> `ruff check .` covers them too — list them explicitly, never a blanket `bin/*` (it would
> make ruff try to parse a bash hook as Python). jscpd still keys off extensions, so verbatim
> duplication in extensionless scripts remains uncovered (acceptable).

## Ruby/Rails: ERB + security + correctness tooling (v17)

Beyond rubocop/flay/debride, v17 brings the Rails stack in line with modern practice (and with
Rails 8's own default `bin/rails new` CI). All are glob-gated in `hk.pkl` and mirrored in
`ci.ruby.yml`; the gems go in the Gemfile dev group (`require: false`) except `strong_migrations`
(a runtime railtie in `:development`). Non-Rails Ruby gems (no `app/` views) get none of these.

- **herb** — HTML-aware ERB toolchain. `herb analyze app/` is pure libherb (parse errors, offline);
  `herb lint app/` enforces `.herb.yml`'s HTML/ERB/a11y rules and delegates to
  `npx @herb-tools/linter` (version pinned to the herb gem, so deterministic — needs `node`, which
  the Ruby template already pins for jscpd). `lint-on-edit` applies `herb lint --fix` on write.
- **brakeman** — Rails SAST (`-q --no-pager --exit-on-warn`); offline, gates. Mirrors Rails 8's
  `scan_ruby` job.
- **bundler-audit** — gem CVE / insecure-source scan. Best-effort `bundle-audit update` refreshes
  the advisory DB when online (swallowed offline), then `bundle-audit check` gates against the
  bundled-or-updated DB — a real gate either way, just fresher with network.
- **importmap audit** — scans pinned JS for advisories (`bin/importmap audit`), guarded so it skips
  cleanly on jsbundling/esbuild apps. Mirrors Rails 8's `scan_js` job.
- **rubocop plugins** — enabled via `.rubocop.yml`'s `plugins:` key; no new step, they enrich the
  existing `bin/rubocop` run. **Omakase repos** (`rubocop-rails-omakase`) add only
  `rubocop-minitest`/`rubocop-rspec`: omakase already loads rubocop-rails + rubocop-performance and
  disables both departments wholesale (formatter-plus-a-few-lints; Security off too — brakeman
  covers it), so re-adding them is inert and force-enabling their cops fights the omakase
  philosophy. **Plain-rubocop repos** add the full `rubocop-rails` + `rubocop-performance` +
  `rubocop-minitest`/`-rspec`.
- **strong_migrations** — runtime gem that raises on unsafe migrations (NOT NULL adds, column
  removes, in-transaction backfills). Not a CI/hk step; goes in the **main Gemfile (ungrouped, not
  `require: false`)** — its `config/initializers/strong_migrations.rb` references the
  `StrongMigrations` constant in every environment, so a `:development`-only gem crashes the
  test/production boot; ungrouped also lets it guard production `db:migrate`. Install with
  `bin/rails g strong_migrations:install`. Only enforces on Postgres/MySQL — a no-op on SQLite.
- **database_consistency** — compares model validations/associations to the DB schema (missing
  NOT NULL, indexes, etc.). Needs a reachable DB, so the hk step probes with `bin/rails runner
  "ActiveRecord::Base.connection"` and **gates when a dev/test DB is up, skips (exit 0) otherwise**
  so a fresh/un-migrated worktree won't block commits; in CI it gates unconditionally (the `test`
  job prepares the DB). Keep the probe loop-free — hk's internal `sh` aborts on `while read` in
  `$(...)`.
- **fasterer** — perf anti-pattern advisory (`|| true`).

## GitHub Actions checks: actionlint + zizmor (v18)

v16 made workflow *supply chain* safe (SHA-pinned actions, read-only `GITHUB_TOKEN`). v18 adds two
static analyzers that catch the *workflow-authoring* problems a pin can't, on every stack (every
stack ships a `ci.yml`): **actionlint** for correctness and **zizmor** for security. Both run as
hk built-ins at pre-commit and in one CI `actions-lint` job. Together they are the automated
enforcement of the **[[github-actions]]** skill's checklist.

- **Tools.** `zizmor = "latest"` (registry `aqua:zizmorcore/zizmor`) and `actionlint = "latest"`
  (`aqua:rhysd/actionlint`) in `mise.toml`, so `mise.lock` checksum-verifies both; the bare
  binaries are on PATH for the hk steps and CI.
- **actionlint (correctness).** `["actionlint"] = (Builtins.actionlint) { check = "actionlint -shellcheck= {{ files }}" }`
  — the built-in globs `.github/workflows/*.yml|yaml`. It catches schema errors (typo'd/misplaced
  keys), invalid `${{ }}` expressions, undefined `needs:`, bad globs, etc. We amend it with
  **`-shellcheck=`** to turn off its shellcheck-of-`run:` integration: the standard's `run:` blocks
  deliberately word-split a file list (`shellcheck $files`), which trips `SC2086`/`SC2035`, and
  real `*.sh` files are already covered by the dedicated `shellcheck` step — so re-shellchecking
  inline `run:` is noise. (Override the `check` command rather than relying on shellcheck being
  absent, because in shell/Go repos shellcheck *is* on PATH.)
- **zizmor (security).** `["zizmor"] = Builtins.zizmor` — globs `.github/workflows/*.yml`,
  `.github/dependabot.yml`, and `**/action.yml`; uses `check_diff` (scans just the changed files).
  Catches credential persistence, `${{ … }}` template injection into `run:`, over-broad per-job
  permissions, dangerous `pull_request_target`/`workflow_run` triggers, and more. No config needed.
- **CI job.** One `actions-lint` job (parallel to `gitleaks`) checks out, installs mise, and runs
  `actionlint -shellcheck=` then `zizmor --no-progress .github/workflows/`. zizmor uses offline
  audits only — no `GH_TOKEN`, so it's deterministic (online GitHub-API audits are skipped; the
  static audits that matter run regardless).
- **`persist-credentials: false` on every `actions/checkout`.** zizmor's `artipacked` audit flags
  a checkout that leaves the job's `GITHUB_TOKEN` in `.git/config` on the runner, where any later
  step (or a compromised action) can read it. The templates set `persist-credentials: false` on
  every checkout; `zizmor --fix=all` applies it mechanically (it's an "unsafe" fix only because a
  job that *pushes* needs the token persisted — those rare jobs keep the default and add a
  `# zizmor: ignore[artipacked]` comment on the `uses:` line).
- **Exit behaviour.** Each tool exits non-zero on a real finding (zizmor at/above the default
  persona's threshold), failing the hk step and the CI job. The shipped templates are clean —
  `actionlint -shellcheck= <file>` and `zizmor --no-progress <file>` both → exit 0.

## Executable bits on shipped scripts (v15)

Any git-tracked file whose **first line is a shebang** must be index mode `100755`. Clones,
CI checkouts, and Claude Code plugin-cache installs all materialize the **git index mode** —
local working-tree permissions never leave the author's machine, and with
`core.fileMode = false` (common on mounted/synced filesystems) even a local `chmod +x` is
invisible to git. The failure shape: every script works for the author, then exits 126
"Permission denied" on every other machine (see the v14 → v15 section in
`upgrade-guide.md` for the incident that motivated this). Fix:
`git update-index --chmod=+x <file>`.

Two gates enforce the same rule so they can't drift:

- **hk `exec-bit-scripts`** (all `hk.<stack>.pkl` templates) — scans `git ls-files -s` for
  `100644` entries whose first line is `#!` and fails the commit, naming the files and the fix.
  The detection is a **single awk** on purpose: hk's internal `sh` aborts on a `while read`
  loop inside a `$(...)` command substitution — even when the substitution exits 0 — so every
  intermediate command must be zero-exit. Don't "simplify" it back to a shell loop; it passes
  under real dash/bash/sh and dies only under hk's runner.
- **CI `lint` job step** (all `ci.<stack>.yml` templates) — the same awk in plain shell. A
  plugin/script-bundle repo whose pytest suite runs in CI should *also* carry the test form
  (see this repo's `tests/test_exec_bits.py`): same rule, plus a sanity assertion that a known
  shipped script is among the detected executables, guarding against the scan silently
  matching nothing.

The shebang heuristic deliberately covers sourced libraries too (e.g. a `lib/common.sh` with a
shebang for shellcheck's benefit): the bit is harmless there, and one blanket rule beats
maintaining an exemption list.

## Duplication: flay vs jscpd (why Ruby runs both)

**flay** parses Ruby to an AST and hashes subtrees, so it catches **structural** duplication even
when identifiers, literals, or whitespace differ (renamed clones) — and verbatim Ruby too. But it
only understands Ruby (`.rb`/`.erb`), and it **exits 0** (advisory; great for refactoring sweeps,
useless as a gate). **jscpd** is a **token-based** (Rabin-Karp) detector across 200+ formats: it
catches verbatim copy-paste in **any** language and **gates** CI via its `threshold` reporter.

A Rails app is polyglot — Stimulus JS, CSS/SCSS, ERB markup all carry duplication that flay can't
parse — so **Ruby/Rails runs both**: jscpd as the cross-language enforcing gate (incl. Ruby
verbatim), flay as advisory Ruby structural depth. **Python/shell run jscpd only** (no
widely-used AST dup detector for Python; pylint's duplicate-code is token-ish and heavy). The cost
is that jscpd needs Node, so Ruby repos gain a Node dependency — acceptable because Rails already
ships JS/CSS worth checking. flay can be promoted from advisory to a hard gate later via a
`--mass` threshold wrapper if wanted.

## Claude Code plugin repos

**Claude Code plugin repos** (and any script-bundle repo) carry two extra requirements:

1. **All bundled scripts are tested.** Use the bundled-script test setup: a **dev-only**
   `pyproject.toml` (`[tool.uv] package = false`, deps in `[dependency-groups] dev`, see
   `templates/pyproject.plugin.toml`) and a `tests/` suite that runs each
   script/CLI/hook **as a subprocess** and asserts on real output
   (`templates/test_scripts.example.py`). The `pytest` hk step + the CI `test`
   job run it. No script ships without a test exercising it.
2. **Python scripts use uv + PEP 723 inline metadata.** Each Python script is self-contained:
   shebang `#!/usr/bin/env -S uv run --script` and a `# /// script … # ///` block declaring
   `requires-python` + `dependencies`, run via `uv run`. No repo-level runtime deps; mirror the
   script's libs into the dev group so tests can import them. (Mixed shell + Python is fine —
   shell via `shellcheck`/`shfmt`, Python via uv/PEP 723.)

## `.gitignore` gotchas

The standard ships **no `.gitignore` template** — Claude's defaults are usually right. Just
check these gotchas, where the default may be wrong or the standard's tooling expects something:

- **Ignore `.env` / `.env.local`.** The gitleaks step is the safety net; `.gitignore` is the
  first line — keep both. But **commit `fnox.toml`** in solo repos (it holds secret *references*,
  not values); gitignore it only in repos shared with others. See the `env-to-fnox` skill.
- **But `.env` must also be allowlisted in `.gitleaks.toml`** (committed, v10+) — `gitleaks dir`
  scans gitignored files too, so the ignored `.env`/`log/`/`*.key` still trip the scan without the
  allowlist. The same gitignored `.env` that this silences is what triggers the `suggests_fnox`
  nudge toward `env-to-fnox`. See "gitleaks whole-tree allowlist" in `../SKILL.md`.
- **Commit lockfiles, don't ignore them** (`mise.lock`, `uv.lock`, `Gemfile.lock`). The standard
  pins tools for reproducibility; a library-flavored default that drops lockfiles defeats that.
- **`mise.local.toml` is the ignorable one; `mise.toml` is committed** — the `DEV_ENV_VERSION`
  stamp lives in the committed file, machine-local overrides go in `mise.local.toml`.
- **Keep `.venv/` ignored** — CI's `git ls-files` and `.jscpd.json`'s `ignore` both assume it.
  The default already covers this; just don't un-ignore it.

## AGENTS.md symlink (advisory, not gated)

**Recommended, not part of the version-checked standard** — the checker doesn't look for it and
it never blocks an upgrade. Project instructions live in `CLAUDE.md`, but other AI coding tools
read `AGENTS.md`. To keep one source of truth, make `AGENTS.md` the real file and symlink
`CLAUDE.md` → `AGENTS.md`, then commit both. Migrate an existing real `CLAUDE.md` into
`AGENTS.md` first (never clobber it); on native Windows symlinks need Developer Mode, but WSL2
is fine. The coding-onboarding `getting-started` skill has the idempotent recipe.
