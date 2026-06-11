# The standard (v12) — full specification

The detailed per-artifact requirements behind the summary in `../SKILL.md`. Read this before
writing or editing any of the standard's files. The version here tracks `../VERSION` (guarded
by the test suite).

## Required artifacts

A repo is **compliant at v12** when it has all of:

- **`mise.toml`** — `[tools]` pins `hk`, `pkl`, the stack tool (`uv` for Python), `gitleaks`,
  and (all stacks that run jscpd — Python, shell, Ruby/Rails, **and JS/TypeScript**) `node` (to
  run jscpd via `npx`; for JS it also serves as the stack tool); `[settings] lockfile = true`;
  `[env]` carries the version stamp `DEV_ENV_VERSION = "12"`.
- **`mise.lock`** (committed) — records resolved tool versions + per-platform checksums so installs
  are reproducible and checksum-verified. See "Lockfile & supply-chain verification" in `../SKILL.md`.
- **`.jscpd.json`** (all stacks) — duplication config: `minTokens 70`, `threshold 0`,
  `reporters ["ai","threshold"]`, `gitignore true`, path excludes under `ignore` — the key must
  be `ignore`, **not** `ignorePattern` (inert for paths in jscpd v5; see the exclusions note)
  (vendored/generated dirs incl. `node_modules`, `vendor`, `dist`, `build`). The `missing-test-reminder` hook also reads this file to skip those dirs.
- **`hk.pkl`** — amends a pinned hk `Config.pkl`, defines per-stack linter steps **plus the
  audits (dead-code + duplication), `gitleaks`, and `check-added-large-files`** (`Builtins.*`),
  and wires `pre-commit` (`fix = true`, `stash = "git"`), `fix`, and `check` hooks. Every step —
  including the audits — lives in one `linters` mapping shared by all three hooks, so the audits
  **run on pre-commit** too (each is glob-gated, so a docs-only commit skips them); `check` is
  just the same set under one name that CI invokes.
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
| Ruby/Rails | `bin/rubocop` (omakase) | `bin/rails test` | gitleaks | `check-added-large-files` | `debride` | `jscpd` (polyglot gate) + `flay` (Ruby structural, advisory) |
| JS/TypeScript | `prettier` (check/fix) | — | gitleaks | `check-added-large-files` | — | `jscpd` (`-f javascript,typescript,css,scss`) |
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
> **jscpd version policy (pre-commit + CI):** the step neither pins a fixed version nor calls
> `@latest` blindly. It tracks latest with a **4-day cooldown** — the same supply-chain seasoning
> as the dependency cooldowns (see "Dependency cooldown (supply-chain)" in `../SKILL.md`) — via
> `npx --before=<4 days ago>`, which
> resolves the newest release that has existed at least 4 days. It's **floored at v5** (the major
> `.jscpd.json` targets) so the cooldown can't regress to v4 while the v5 line is still <4 days
> old; if the cooldown pick is below the floor the step falls back to `latest`. It also **degrades
> gracefully offline**: when the registry is unreachable it runs the cached jscpd, and when nothing
> is cached it warns and passes rather than blocking the commit. The cooldown resolve costs one
> registry round-trip (~0.9s) per commit that stages matching files.
>
> Configuring exclusions:
> - **Exclude paths** with `ignore` (a glob array) in `.jscpd.json`. **`ignorePattern` does NOT
>   exclude paths in jscpd v5** — it's silently inert there, which let CI scan the
>   CI-installed `vendor/bundle` gems and fail on their clones (booking-overview, 2026-06-10;
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
>   (Ruby), `-f javascript,typescript,css,scss` (JS/TypeScript). Add `ignore` globs on top to skip
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

1. **All bundled scripts are tested.** Follow [`readoc`](https://github.com/mickzijdel/readoc)'s
   setup: a **dev-only**
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
