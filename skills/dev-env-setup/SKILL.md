---
name: dev-env-setup
version: 4.0.0
description: |
  Audit a repo against Mick's dev-environment standard (mise pinning tools, an hk
  pre-commit hook running linters/tests + gitleaks, a GitHub Actions workflow that
  mirrors those checks, and project docs — README.md + CLAUDE.md recording pinned
  package versions) and set it up or upgrade it. Use when a repo of Mick's is missing
  the standard setup, when the dev-env-reminder hook flags a gap, when the user mentions
  hk/mise/gitleaks/"my dev setup", or when starting a new repo. Tracks a standard version
  via DEV_ENV_VERSION in mise.toml and upgrades behind repos using references/upgrade-guide.md.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - Task
  - AskUserQuestion
---

# dev-env-setup

Bring a repo up to **Mick's dev-environment standard** and keep it there. Reference
implementations: [`bedlam-bacs`], [`readoc`] (Python), [`booking-overview`] (Rails).

## The standard (v6)

A repo is **compliant at v6** when it has all of:

- **`mise.toml`** — `[tools]` pins `hk`, `pkl`, the stack tool (`uv` for Python), `gitleaks`,
  and (all stacks that run jscpd — Python, shell, **and Ruby/Rails**) `node` (to run jscpd via
  `npx`); `[settings] lockfile = true`; `[env]` carries the version stamp `DEV_ENV_VERSION = "6"`.
- **`mise.lock`** (committed) — records resolved tool versions + per-platform checksums so installs
  are reproducible and checksum-verified. See "Lockfile & supply-chain verification".
- **`.jscpd.json`** (all stacks) — duplication config: `minTokens 70`, `threshold 0`,
  `reporters ["ai","threshold"]`, `gitignore true`, path excludes under `ignorePattern`.
- **`hk.pkl`** — amends a pinned hk `Config.pkl`, defines per-stack linter steps **plus the
  audits (dead-code + duplication), `gitleaks`, and `check-added-large-files`** (`Builtins.*`),
  and wires `pre-commit` (`fix = true`, `stash = "git"`), `fix`, and `check` hooks. Every step —
  including the audits — lives in one `linters` mapping shared by all three hooks, so the audits
  **run on pre-commit** too (each is glob-gated, so a docs-only commit skips them); `check` is
  just the same set under one name that CI invokes.
- **`.github/workflows/ci.yml`** — runs the same lint + test + gitleaks checks, plus an
  `audit` job (dead-code + duplication + a large-file guard), on push/PR.
- **`README.md`** and **`CLAUDE.md`** (added in v3) — both present at the repo root, and both
  recording the **current versions of the project's key packages** (main framework, Tailwind,
  Bootstrap, etc.) so the human-facing docs don't drift from the manifests. The checker only
  enforces that both files exist; keeping the version numbers accurate is the writer's job (the
  `latest-deps-reminder` hook nudges Claude to update them on every manifest edit). If either
  doc is missing, the setup/upgrade flow **dispatches a subagent to create it** — see
  "Project docs (README + CLAUDE.md)".
- **Dependency cooldown** (added in v6) — a Python repo pins a 4-day uv cooldown in
  `pyproject.toml` (`[tool.uv] exclude-newer`), so newly-published deps aren't resolved until
  they've been public long enough for a malicious release to be caught and yanked. The checker
  enforces this on Python stacks; Ruby and JS repos get the same window via their own package
  manager (recommended, not gated) — see "Dependency cooldown (supply-chain)".

Per-stack checks (see `references/templates/`). **When each runs:** every step — linters,
large-file, and the dead-code + duplication audits — runs on pre-commit (each glob-gated) and
again in `check`/CI.
| Stack | Linters (pre-commit) | Tests | Secrets | Large file | Dead code (pre-commit) | Duplication (pre-commit) |
|-------|---------|-------|---------|------------|-----------|-------------|
| Python | `ruff check`, `ruff format` (via `uv run`) | `pytest` | gitleaks | `check-added-large-files` | `vulture` | `jscpd` |
| Ruby/Rails | `bin/rubocop` (omakase) | `bin/rails test` | gitleaks | `check-added-large-files` | `debride` | `jscpd` (polyglot gate) + `flay` (Ruby structural, advisory) |
| Shell / CC plugin | `shellcheck`, `shfmt`, `ruff` (any `.py`) | `pytest` over bundled scripts (see below) | gitleaks | `check-added-large-files` | `vulture` (any `.py`) | `jscpd` |

> Dead-code (`vulture`/`debride`) and duplication (`jscpd`/`flay`) run on pre-commit alongside the
> linters (each is glob-gated, so they only fire when a matching file is staged) and again in
> `check`/CI. They're fast enough warm — vulture ~0.15s, jscpd ~1s (cooldown resolve + scan) — and
> catching dead code / clones before push beats finding out in CI. Thresholds are tunable — see
> `references/upgrade-guide.md`.
>
> **jscpd** runs via `npx` (its v5 Rust engine — the `cpd` binary — ships through npm optional
> platform packages that `npx` resolves but the mise `npm:` backend doesn't), reading
> `.jscpd.json`. It uses the agent-friendly **`ai`** reporter (compact clone output) and the
> **`threshold`** reporter (CI gate). (Making it a real mise tool is deferred: `cargo:jscpd` works
> but needs a Rust toolchain per repo, and there are no prebuilt release binaries for an
> `aqua`/`ubi` backend — see `references/dropped-from-nate.md` for the tested comparison and
> revisit triggers, 2026-06-09.)
>
> **jscpd version policy (pre-commit + CI):** the step neither pins a fixed version nor calls
> `@latest` blindly. It tracks latest with a **4-day cooldown** — the same supply-chain seasoning
> as the [dependency cooldowns](#dependency-cooldown-supply-chain) below — via `npx --before=<4 days ago>`, which
> resolves the newest release that has existed at least 4 days. It's **floored at v5** (the major
> `.jscpd.json` targets) so the cooldown can't regress to v4 while the v5 line is still <4 days
> old; if the cooldown pick is below the floor the step falls back to `latest`. It also **degrades
> gracefully offline**: when the registry is unreachable it runs the cached jscpd, and when nothing
> is cached it warns and passes rather than blocking the commit. The cooldown resolve costs one
> registry round-trip (~0.9s) per commit that stages matching files.
>
> Configuring exclusions:
> - **Exclude paths** with `ignorePattern` (a glob array) in `.jscpd.json`. (Plain `ignore` has
>   no effect; `gitignore: true` already skips gitignored paths.)
> - **Restrict which file types are scanned** with `-f` on the command — there is no config
>   option for it, and without it jscpd also scans markdown/yaml/json and trips `threshold 0` on
>   README/CI/template duplication. Each stack passes the `-f` matching its glob: `-f python`
>   (Python), `-f python,bash` (shell/plugin), `-f ruby,erb,javascript,typescript,css,scss,sass,vue`
>   (Ruby). Add `ignorePattern` on top to skip tracked code (e.g. generated `db/schema.rb`). For extensionless **PEP 723** scripts (e.g. `bin/foo`),
> jscpd keys off extensions, so duplication on extensionless scripts isn't auto-covered. To
> auto-fix clones, agents can run
> `npx skills add https://github.com/kucherenko/jscpd --skill dry-refactoring`.

> **Extensionless scripts (CC-plugin `bin/foo`, hooks) are linted by shebang — no glob
> surgery needed.** hk's `shellcheck`/`shfmt`/`ruff` builtins match by extension (`**/*.sh`,
> `**/*.py`), so they'd silently skip the extensionless executables plugin repos keep in
> `bin/`. The shell template (`hk.shell.pkl`) therefore carries companion steps —
> `shellcheck-scripts`, `shfmt-scripts`, `ruff-check-scripts`, `ruff-format-scripts` — that
> detect such files by **shebang** (`git ls-files | xargs -r grep -lE '^#!.*…'`), the same way
> the `vulture` step already does, and `ci.shell.yml` mirrors them. They're **check-only**
> (a flagged script is fixed by hand or `ruff check --fix`/`shfmt -w`) and run full-tree.
> So you no longer hand-add extensionless CLIs to hk globs. `[tool.ruff] extend-include` is
> still worth setting (in `pyproject.toml`) to the **Python** extensionless scripts so a bare
> `ruff check .` covers them too — list them explicitly, never a blanket `bin/*` (it would
> make ruff try to parse a bash hook as Python). jscpd still keys off extensions, so verbatim
> duplication in extensionless scripts remains uncovered (acceptable).

### Duplication: flay vs jscpd (why Ruby runs both)

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

**Claude Code plugin repos** (and any script-bundle repo) carry two extra requirements:

1. **All bundled scripts are tested.** Follow [`readoc`]'s setup: a **dev-only**
   `pyproject.toml` (`[tool.uv] package = false`, deps in `[dependency-groups] dev`, see
   `references/templates/pyproject.plugin.toml`) and a `tests/` suite that runs each
   script/CLI/hook **as a subprocess** and asserts on real output
   (`references/templates/test_scripts.example.py`). The `pytest` hk step + the CI `test`
   job run it. No script ships without a test exercising it.
2. **Python scripts use uv + PEP 723 inline metadata.** Each Python script is self-contained:
   shebang `#!/usr/bin/env -S uv run --script` and a `# /// script … # ///` block declaring
   `requires-python` + `dependencies`, run via `uv run`. No repo-level runtime deps; mirror the
   script's libs into the dev group so tests can import them. (Mixed shell + Python is fine —
   shell via `shellcheck`/`shfmt`, Python via uv/PEP 723.)

**Applicability:** the standard applies to a repo with a recognized stack
(`pyproject.toml`/`Gemfile`/`package.json`) **or** any scripts (`*.sh`, `bin/*`, `*.py`) —
including Claude Code plugin repos. A prose/skills-only repo with no scripts is exempt.

## Why this shape (keep / drop vs. Nate's setup)

This is trimmed from [Nate Berkopec's `dev-env-setup`](https://github.com/nateberkopec/dotfiles/tree/main/files/home/.claude/skills/dev-env-setup)
to what Mick's repos actually use. **Kept:** mise-as-tool-manager, hk parallel pre-commit,
ruff/pytest + rubocop/rails-test, CI-mirrors-hk. **Added:** gitleaks (defense-in-depth with
[[env-to-fnox]]) and shellcheck/shfmt for shell/plugin repos. **Dropped** (and why) lives in
[`references/dropped-from-nate.md`](references/dropped-from-nate.md) — revisit those before
proposing additions.

## Workflow

1. **Audit.** Run the checker and read its output:
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/skills/dev-env-setup/scripts/dev_env_check.sh" .
   ```
   (`$CLAUDE_PLUGIN_ROOT` is set when run as a plugin; otherwise use the skill dir path.) It
   prints `status` = `not-applicable` | `needs-setup` | `needs-upgrade` | `compliant`, plus
   `stack`, `repo_version`, and `current_version`.
   - `not-applicable` or `compliant` → stop; tell the user, change nothing.
   - `needs-setup` → go to step 2 (fresh setup).
   - `needs-upgrade` → go to step 4 (upgrade).

2. **Fresh setup — detect the stack** (the checker reports it) and confirm with the user if
   ambiguous (e.g. a plugin that is also a Python package).

3. **Fresh setup — write the config** from `references/templates/` for the stack:
   copy `mise.<stack>.toml` → `mise.toml`, `hk.<stack>.pkl` → `hk.pkl`,
   `ci.<stack>.yml` → `.github/workflows/ci.yml`, and (all stacks) `.jscpd.json` → repo root.
   Adjust specifics (default branch name, Python version). Extensionless CLIs like `bin/foo`
   are covered automatically by the shell template's shebang companion steps — no hk-glob
   surgery; just point `[tool.ruff] extend-include` at the Python ones (see the extensionless
   note above). The templates
   already include `DEV_ENV_VERSION`, gitleaks, and the audit checks. **Add the audit deps**
   the templates assume: `vulture` to the Python dev group; `flay` + `debride` to the Ruby
   Gemfile dev group (mise pulls `node` for jscpd, which runs via `npx`, on all jscpd stacks
   incl. Ruby). **For a
   shell/plugin repo**, also add the [`readoc`]-style dev project (`pyproject.plugin.toml` →
   `pyproject.toml`, fill in the name) and a `tests/` suite (`test_scripts.example.py` as a
   starting point) so every bundled script is exercised, and give each Python script the
   `uv run --script` shebang + PEP 723 block. **Before writing the workflow, pin every GitHub
   Action to its current latest version** — the template versions are a snapshot and go stale.
   See "Keeping GitHub Actions current". After the tools are written, generate the lockfile
   (`mise install && mise lock`) and **commit `mise.lock`** — see "Lockfile & supply-chain
   verification".

4. **Upgrade — apply the guide.** Read [`references/upgrade-guide.md`](references/upgrade-guide.md)
   and apply every section **strictly newer** than `repo_version`, in order. Then set
   `DEV_ENV_VERSION` in `mise.toml` to `current_version`. (Existing v0 repos — hk/mise/CI that
   predate this standard — add the stamp + gitleaks + large-file + the dead-code/duplication
   audits per the v0 → v1 section.) **Also audit the existing workflow's Actions** and bump any
   that are behind latest (same recipe below).

5. **Ensure project docs (README.md + CLAUDE.md)** — required from v3. The checker reports
   `has_readme` / `has_claude`. If either is missing (or, on a substantive setup/upgrade, looks
   stale), **dispatch a subagent** (via `Task`) to write it rather than doing it inline — see
   "Project docs (README + CLAUDE.md)" below for the exact brief. The docs must record the
   current versions of the project's key packages, read from the manifests/lockfiles you just
   set up (not from memory).

6. **Repo ownership.** If the repo is Mick's, **commit** `mise.toml`/`hk.pkl`/`ci.yml`. If it
   is someone else's repo you only contribute to, do **not** commit them — add `hk.pkl` and
   `mise.toml` to `.git/info/exclude` instead. (This mirrors the dev-env-reminder hook's
   ownership rule.)

7. **Verify** (do this, don't assume):

   > **`mise trust` first (gate on the user).** A freshly written or cloned `mise.toml` is
   > untrusted, so `mise install` fails with "Config files … are not trusted" until you run
   > `mise trust` once for the repo. Trusting a config lets it run arbitrary task/env code, so
   > **ask the user to approve before running `mise trust`** — don't auto-trust.

   ```bash
   mise trust             # one-time, only after the user approves (see note above)
   mise install            # provision hk, pkl, gitleaks, etc. (verifies against mise.lock)
   mise lock               # ensure mise.lock carries all-platform checksums; commit it
   hk install              # install the git hooks
   hk run check            # all steps, including gitleaks, must pass
   bash "$CLAUDE_PLUGIN_ROOT/skills/dev-env-setup/scripts/dev_env_check.sh" .   # → status=compliant
   bash "$CLAUDE_PLUGIN_ROOT/skills/dev-env-setup/scripts/check_action_refs.sh" .github/workflows  # every uses: pin resolves
   ```
   Confirm `mise.lock` is present and committed, and that `README.md` + `CLAUDE.md` exist
   (`has_readme=1 has_claude=1`). Run the project's own tests too (`uv run pytest` /
   `bin/rails test`). Report real output.

## Project docs (README + CLAUDE.md)

From v3, a compliant repo has both a **README.md** and a **CLAUDE.md** at its root, and both
record the **current versions of the project's key packages** (main framework, Tailwind,
Bootstrap, etc.). Humans read the README; Claude reads CLAUDE.md — and both drift from the
manifests fast, so the version numbers are the point.

**When a doc is missing, dispatch a subagent to write it** (use the `Task` tool — don't write
these inline; doc-writing is a self-contained job and the README in particular benefits from a
focused pass). Give the subagent this brief:

- **Read the real versions first.** Pull key-package versions from the resolved manifests/
  lockfiles in this repo — `uv.lock`/`pyproject.toml`, `Gemfile.lock`, `package.json` — **never
  from memory** (training data goes stale). For a Rails app that means Rails, Ruby, and any
  CSS/JS framework (Tailwind, Bootstrap, Hotwire/Turbo); for Python, the framework + Python
  version; for a JS app, the framework + Tailwind/Bootstrap.
- **README.md** — use the **[[github-readme]]** skill for structure and tone. Include a short
  "Built with" / tech-stack section listing those key packages **with their pinned versions**.
- **CLAUDE.md** — project instructions for Claude: how to run the app, test, and lint (mirror the
  hk/mise setup just written), plus the same key-package-versions list so Claude doesn't guess.
  If a `/init` exists in the environment it's a fine starting point, but the versions must come
  from the manifests.
- **Keep both in sync** with each other and with the manifests; updating both is preferred.

If both docs already exist, leave them — only refresh the version numbers if they're visibly
stale relative to the manifests. The `latest-deps-reminder` hook keeps them current on
subsequent manifest edits, so this skill only bootstraps them.

## Keeping GitHub Actions current

The `uses:` versions in `references/templates/ci.*.yml` are a snapshot from when the template
was written — they drift. **Whenever you write or touch a workflow** (fresh setup *and*
upgrade), check every Action against its latest release and pin to the latest major tag.

For each `uses: OWNER/REPO@vX`, find the current latest tag and bump it:

```bash
# Latest published release tag for an action (e.g. v4.2.1):
gh release view --repo actions/checkout --json tagName -q .tagName
# Fallback if the action publishes no GitHub Releases — newest version tag:
gh api repos/actions/checkout/tags --jq '.[].name' | grep -E '^v[0-9]' | sort -V | tail -1
```

Pin to the latest **major** (`@v4`) unless the user wants an exact tag. Do this for the Actions
in the templates — currently `actions/checkout`, `astral-sh/setup-uv`, `ruby/setup-ruby`,
`actions/upload-artifact`, `gitleaks/gitleaks-action`, `jdx/mise-action` — and any others a repo
already uses.
Caveat: some actions don't publish a floating major tag for their newest release (e.g.
`astral-sh/setup-uv` ships `v8.x` releases but only floats `@v1`…`@v7`), so `@v8` fails to
resolve in CI. Always verify the chosen ref actually exists —
`git ls-remote --tags --refs https://github.com/OWNER/REPO refs/tags/<ref>` — and if the floating
major is missing, pin the exact latest release tag (e.g. `astral-sh/setup-uv@v8.2.0`) instead.
When upgrading an existing repo, list each Action with its current vs. latest version and bump
the stale ones in the same pass. If `gh` is unavailable or unauthenticated, say so and ask Mick
to check, rather than guessing a version.

**Always verify the pins resolve before finishing.** After writing or bumping any `uses:` pin,
run the bundled checker — it `git ls-remote`s every referenced action and fails on any ref that
doesn't exist on the remote, catching the floating-major trap above before CI does:

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/dev-env-setup/scripts/check_action_refs.sh" .github/workflows
# → "N ok, 0 unresolved" and exit 0; any FAIL line is a pin that will break CI.
```

(The `ci-action-ref-reminder` hook nudges you to run this whenever a workflow is edited.)

## Lockfile & supply-chain verification

The mise toolchain is pinned reproducibly via a committed **`mise.lock`** plus
`[settings] lockfile = true` in `mise.toml`. Tools stay spec'd `"latest"`; the lock records what
that resolved to, so every machine and CI install the same artifacts and verify them.

Three layers (the latter two apply per the tool's aqua-registry entry — most registry tools, incl.
`gitleaks`, are aqua-backed):

- **Checksums** (always) — mise stores each artifact's SHA per OS/arch in `mise.lock` and re-checks
  on every install; a mismatch fails the install. Defends against tampered/swapped downloads.
- **Cosign signatures** — verifies the artifact was signed by the project's expected (keyless/OIDC)
  identity. Defends against a forged release.
- **SLSA provenance / attestations** — verifies the artifact was built by the expected pipeline from
  the expected source. Defends against a compromised build system.

**Day-to-day flow:**

| Action | Command | Effect |
|--------|---------|--------|
| Reproduce | `mise install` | installs exactly what `mise.lock` says, verifying checksums |
| Record | `mise lock` | backfills all-platform checksums for the current specs |
| Upgrade | `mise upgrade` | re-resolves `"latest"`, rewrites `mise.lock` — commit the diff |

So upgrades are explicit (`mise upgrade` + a reviewable `mise.lock` diff) rather than silent drift,
while the spec stays `"latest"` so the `latest-deps-reminder` hook still nudges toward current
versions. **Commit `mise.lock`** alongside `mise.toml`.

**Gap:** this covers only mise-managed tools. The `npx` jscpd audit step isn't mise-pinned (jscpd
5.x ships only as npm-distributed Rust platform packages — no clean mise backend); instead it
tracks latest on a 4-day cooldown floored at v5 (see the jscpd version-policy note above). Project
deps lock separately via `uv.lock` / `Gemfile.lock`.

## Dependency cooldown (supply-chain)

Hold off on freshly-published package versions for **4 days** before resolving them. Most malicious
releases (the 2026 Shai-Hulud npm waves, the axios / litellm incidents) are detected and yanked
within hours-to-days of publication, so a short cooldown means you are never the one who installs a
compromised version in the window before the community catches it. The standard already applies this
to its own tooling — the jscpd audit step resolves via `npx --before=<4 days ago>` (see the jscpd
version policy above) — and this section extends the same 4-day window to a repo's own runtime / dev
dependencies.

Set it **per repo** so every developer and CI run enforce the same window, and (if not already set)
once **machine-wide** as a default. An existing lockfile (`Gemfile.lock`, `uv.lock`,
`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`) is honoured as-is, so adding a cooldown never
disturbs already-locked versions — it only gates *new* resolutions.

**Repo guard** — pick the row matching the repo's package manager (detect by lockfile):

| Manager | Where | Setting (4-day window) |
|---------|-------|------------------------|
| **uv** (Python, ≥ 0.9.17) | `pyproject.toml` `[tool.uv]` | `exclude-newer = "4 days"` |
| **Bundler** (Ruby, ≥ 4.0.13) | `Gemfile` source line | `source "https://rubygems.org", cooldown: 4` |
| **npm** (≥ 11.10.0) | `.npmrc` | `min-release-age=4` |
| **pnpm** (11+) | `pnpm-workspace.yaml` | `minimumReleaseAge: 5760` (minutes) |
| **yarn** (Berry 4.10+) | `.yarnrc.yml` | `npmMinimalAgeGate: 5760` (minutes — use a raw count; the `4d` suffix has a parse bug) |
| pip (≥ 26.1, no uv) | per install | `--uploaded-prior-to=P4D` (or `pip.conf` `[install]`/`[global]`) |

Only **uv** is checker-enforced for Python repos (see "The standard (v6)"); the rest are recommended
and applied by the setup/upgrade flow when the matching lockfile is present. `exclude-newer` accepts
a rolling duration (`"4 days"` / `"P4D"`) or an absolute date — a duration is the right choice here
so the window moves forward with the current date.

**Global guard (if missing)** — a machine-wide default so a repo that hasn't opted in still gets a
floor:

| Manager | Command | Writes |
|---------|---------|--------|
| uv | add `exclude-newer = "4 days"` to `~/.config/uv/uv.toml` | user uv config |
| Bundler | `bundle config set --global cooldown 4` | `~/.bundle/config` (`BUNDLE_COOLDOWN`) |
| npm | `npm config set min-release-age 4 --location=user` | `~/.npmrc` |
| pnpm | `pnpm config set minimumReleaseAge 5760 --global` | `~/.config/pnpm/config.yaml` (pnpm 11 moved global settings to YAML) |
| yarn | `yarn config set --home npmMinimalAgeGate 5760` | `~/.yarnrc.yml` |

The per-repo setting takes precedence over the global one, so a repo can still override it — e.g.
drop to `0` (or `cooldown: 0`, `exclude-newer` unset) to take a fresh release immediately during an
urgent upgrade. For one-off exceptions *inside* the window, uv has `exclude-newer-package`, pnpm
`minimumReleaseAgeExclude`, and yarn `npmPreapprovedPackages` (npm has no per-package exclude yet).

**Sources:** [RubyGems blog, Jun 2026](https://blog.rubygems.org/2026/06/03/cooldown-let-new-gems-be-vetted.html) ·
[uv `exclude-newer`](https://docs.astral.sh/uv/concepts/resolution/) ·
[minimum release age across npm/pnpm/yarn (gist)](https://gist.github.com/mcollina/b294a6c39ee700d24073c0e5a4e93104) ·
[cooldowns.dev](https://cooldowns.dev/)

## Notes

- The version stamp is the single source of truth in `references/../VERSION`; the reminder hook
  reads the same file, so a repo on an older stamp gets flagged automatically.
- Never auto-run this from a hook — it's invoked by Mick (or offered by the reminder), and it
  writes commit-tracked config, so confirm before committing.

### `.gitignore`

The standard ships **no `.gitignore` template** — Claude's defaults are usually right. Just
check these gotchas, where the default may be wrong or the standard's tooling expects something:

- **Ignore `.env` / `.env.local`.** The gitleaks step is the safety net; `.gitignore` is the
  first line — keep both. But **commit `fnox.toml`** in solo repos (it holds secret *references*,
  not values); gitignore it only in repos shared with others. See [[env-to-fnox]].
- **Commit lockfiles, don't ignore them** (`mise.lock`, `uv.lock`, `Gemfile.lock`). The standard
  pins tools for reproducibility; a library-flavored default that drops lockfiles defeats that.
- **`mise.local.toml` is the ignorable one; `mise.toml` is committed** — the `DEV_ENV_VERSION`
  stamp lives in the committed file, machine-local overrides go in `mise.local.toml`.
- **Keep `.venv/` ignored** — CI's `git ls-files` and `.jscpd.json`'s `ignore` both assume it.
  The default already covers this; just don't un-ignore it.

[`bedlam-bacs`]: https://github.com/EdinburghUniversityTheatreCompany/bacs-tool
[`readoc`]: https://github.com/mickzijdel/readoc
[`booking-overview`]: https://github.com/mickzijdel/booking-overview
