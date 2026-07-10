---
name: dev-env-setup
version: 4.7.0
description: |
  Audit a repo against an opinionated dev-environment standard (mise pinning tools, an hk
  pre-commit hook running linters/tests + gitleaks, a GitHub Actions workflow that
  mirrors those checks, and project docs — README.md + CLAUDE.md recording pinned
  package versions) and set it up or upgrade it. Use when a repo is missing
  the standard setup, when the dev-env-reminder hook flags a gap, when the user mentions
  hk/mise/gitleaks/"my dev setup", when starting a new repo, or to backfill every
  standard-tracking repo after a version bump (fleet mode). Tracks a standard version
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

Bring a repo up to **an opinionated dev-environment standard** and keep it there. It covers
both Python and Rails (Ruby) project types.

## The standard (v20)

A repo is **compliant at v20** when it has all of:

- **`mise.toml`** — tools pinned (`hk`, `pkl`, stack tool, `gitleaks`, `zizmor`, `actionlint`,
  `node` for jscpd), `[settings] lockfile = true` and `minimum_release_age = "4d"`, and the
  `[env]` version stamp `DEV_ENV_VERSION = "20"`.
- **`mise.lock`** (committed) — reproducible, checksum-verified tool installs. See "Lockfile &
  supply-chain verification".
- **`.jscpd.json`** — duplication config (`minTokens 70`, `threshold 0`, path excludes under
  `ignore` — never `ignorePattern`, inert in jscpd v5).
- **`scripts/run-jscpd.sh`** (added in v14) — the shared jscpd runner holding the
  version-cooldown policy; both the hk step and CI's audit job call it (CI with `--require`)
  so the two gates can't drift. Copied verbatim from the template (repo formatters may re-indent it; never hand-edit the logic).
- **`hk.pkl`** — per-stack linters **plus** the dead-code + duplication audits, the
  `exec-bit-scripts` gate, the `actionlint` + `zizmor` GitHub Actions checks, `gitleaks`, and
  `check-added-large-files`, in one `linters` mapping shared by the `pre-commit`/`fix`/`check`
  hooks. Where a hand-rolled step exactly matched an hk built-in it's now the built-in
  (`gitleaks`, `check_added_large_files`, `zizmor`, `actionlint`, and — in the shell stack, where
  `ruff` is a mise tool — `ruff`/`ruff_format`); stacks that run a tool through their package
  manager (`uv run ruff`, `npx prettier`, `bundle exec rubocop`, `golangci-lint`) keep custom
  steps, as the bare-command built-ins would bypass the project-pinned version.
- **Executable-bit gate** (added in v15) — the hk `exec-bit-scripts` step + a CI lint-job
  mirror fail when any tracked shebang file is index mode `100644` (a fresh clone/plugin
  install would get a script that dies with exit 126). Fix:
  `git update-index --chmod=+x <file>`. See "Executable bits on shipped scripts" in
  `references/standard.md` — including why the check is a single awk (hk's internal shell
  aborts on `while read` inside `$(...)`).
- **`.gitleaks.toml`** — allowlists gitignored runtime/secret paths so the whole-tree
  `gitleaks dir` scan doesn't fail on a local `.env`/`log/`. See "gitleaks whole-tree allowlist".
- **`.github/workflows/ci.yml`** — mirrors the hk checks plus an `audit` job; gitleaks runs as
  the MIT-licensed **CLI via mise** (never `gitleaks/gitleaks-action`, which needs a paid
  license on org repos).
- **SHA-pinned actions + read-only token** (added in v16) — in **every file under
  `.github/workflows/`** (not just `ci.yml`), every `uses:` pins a full commit SHA with the
  release tag in a trailing comment (`owner/repo@<sha> # vX.Y.Z`; tags are mutable and a
  takeover repoints them — tj-actions, Trivy), and each workflow declares
  `permissions: { contents: read }` so a compromised step can't write (a deploy that needs
  `pages`/`id-token: write` keeps its own wider block). Checker-enforced across all workflow
  files (`has_sha_pinned_ci`). See "Keeping GitHub Actions current" and the
  **[[github-actions]]** skill's security checklist.
- **GitHub Actions checks: actionlint + zizmor** (added in v18) — hk steps (`Builtins.actionlint`
  and `Builtins.zizmor`, glob-gated to workflow/`action.yml` files) plus one CI `actions-lint` job
  run both over every workflow. **[actionlint](https://github.com/rhysd/actionlint)** catches
  *correctness* — schema/typo errors, bad `${{ }}` expressions, undefined `needs:` (run with
  `-shellcheck=` so its shellcheck-of-`run:` pass doesn't double up with the dedicated shellcheck
  step). **[zizmor](https://docs.zizmor.sh)** catches *security* — credential persistence,
  template injection, over-broad `GITHUB_TOKEN` permissions. As part of zizmor's `artipacked`
  finding, every `actions/checkout` sets `persist-credentials: false` (keeps the repo token out
  of `.git/config` on the runner). Needs `zizmor` + `actionlint` in `mise.toml`; checker-enforced
  (`has_zizmor`, `has_actionlint`). See the **[[github-actions]]** skill.
- **`README.md` + `CLAUDE.md`** — both present, both recording current key-package versions.
  See "Project docs (README + CLAUDE.md)".
- **Dependency cooldown** — Python repos pin a 4-day uv cooldown (checker-enforced); other
  stacks get the same window via their package manager (recommended). See "Dependency cooldown
  (supply-chain)".

**Recommended, advisory (added v19):** a **mise-driven dev container**. Having a `.devcontainer/`
is optional and never gates compliance — but *if* a repo ships one, it must be mise-driven (the
image installs only mise + OS libs; `mise install` in the postCreate `setup.sh` provisions the
toolchain from the bind-mounted `mise.toml`/`mise.lock` — no hardcoded `ruby:`/`node:` base, no
`npm install -g pnpm`). The checker flags drift advisorily (`devcontainer_mise_driven=0`). Scaffold
from `references/templates/devcontainer/`; see "Dev container (mise-driven, advisory)" in
`references/standard.md` and the **[[dockerfile]]** skill.

The full specification — per-artifact requirements, the per-stack linter/audit matrix, the
jscpd version policy and exclusion gotchas, extensionless-script (shebang) linting, the
flay-vs-jscpd rationale, the extra requirements for Claude Code plugin / script-bundle repos,
and the `.gitignore` gotchas — lives in
[`references/standard.md`](references/standard.md). **Read it before writing or editing any of
the standard's files.**

**Applicability:** the standard applies to a repo with a recognized stack
(`pyproject.toml`/`Gemfile`/`package.json`) **or** any scripts (`*.sh`, `bin/*`, `*.py`) —
including Claude Code plugin repos. A prose/skills-only repo with no scripts is exempt.

## Why this shape (keep / drop vs. Nate's setup)

This is trimmed from [Nate Berkopec's `dev-env-setup`](https://github.com/nateberkopec/dotfiles/tree/main/files/home/.claude/skills/dev-env-setup)
to the subset this standard actually uses. **Kept:** mise-as-tool-manager, hk parallel pre-commit,
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
   ambiguous (e.g. a plugin that is also a Python package). Recognized stacks: `pyproject.toml`
   → `python`, `Gemfile` → `ruby`, `package.json` → `javascript`, `go.mod` → `go`; scripts-only
   repos → `shell`.

3. **Fresh setup — write the config** from `references/templates/` for the stack:
   copy `mise.<stack>.toml` → `mise.toml`, `hk.<stack>.pkl` → `hk.pkl`,
   `ci.<stack>.yml` → `.github/workflows/ci.yml`, and (all stacks) `.jscpd.json`,
   `run-jscpd.sh` → `scripts/run-jscpd.sh` (`chmod +x` — and if the repo has
   `core.fileMode = false`, `git update-index --chmod=+x scripts/run-jscpd.sh` after staging,
   or the v15 exec-bit gate will flag it; the shared jscpd runner both the hk
   step and CI call), **and `.gitleaks.toml`** → repo root (the latter keeps `gitleaks dir`'s
   whole-tree scan from failing on gitignored `.env`/`log/`/`*.key` — see "gitleaks
   whole-tree allowlist").
   Adjust specifics (default branch name, Python version). Extensionless CLIs like `bin/foo`
   are covered automatically by the shell template's shebang companion steps — no hk-glob
   surgery; just point `[tool.ruff] extend-include` at the Python ones (see the extensionless
   note in `references/standard.md`). The templates
   already include `DEV_ENV_VERSION`, gitleaks, and the audit checks. **Add the audit deps**
   the templates assume: `vulture` to the Python dev group; for **Ruby** (v17) the dev-group gems
   `flay`, `debride`, `herb`, `brakeman`, `bundler-audit`, `fasterer`, `database_consistency`
   (all `require: false`) plus a rubocop testing plugin `rubocop-minitest` (or `rubocop-rspec`)
   enabled via `.rubocop.yml`'s `plugins:` key — omakase repos stop there (omakase already
   bundles+disables rails/performance, so re-adding them is inert); a plain-rubocop repo also adds
   `rubocop-rails` + `rubocop-performance` — and `strong_migrations` as a runtime gem in the
   **main Gemfile (ungrouped, not `require: false`)** — its initializer references the
   `StrongMigrations` constant in every env, so a `:development`-only gem crashes the test/prod boot (mise pulls `node` for jscpd + `herb
   lint`, which run via `npx`, on all jscpd stacks incl. Ruby); JS repos need no extra audit deps
   (jscpd runs via `npx`, `node` is already the stack tool). **For a Ruby repo**, also copy
   `.fasterer.yml` → repo root — its `exclude_paths` keep fasterer off the bundler-cache
   `vendor/bundle` gems (debride/flay are scoped in the ci/hk commands instead). **For a Go repo**, also copy `golangci.go.yml` → `.golangci.yml` (the v2 config
   `golangci-lint run`/`fmt` both read); no extra audit deps are needed — golangci-lint's
   `unused` covers dead code (so no vulture), and `golangci-lint` itself is mise-pinned. The Go
   template carries `shellcheck`/`shfmt` for any shipped shell script (it ships
   `scripts/run-jscpd.sh`). **For a
   shell/plugin repo**, also add the [`readoc`]-style dev project (`pyproject.plugin.toml` →
   `pyproject.toml`, fill in the name) and a `tests/` suite (`test_scripts.example.py` as a
   starting point) so every bundled script is exercised, and give each Python script the
   `uv run --script` shebang + PEP 723 block. **Before writing the workflow, pin every GitHub
   Action to its current latest version** — the template versions are a snapshot and go stale.
   See "Keeping GitHub Actions current". After the tools are written, generate the lockfile
   (`mise install && mise lock`) and **commit `mise.lock`** — see "Lockfile & supply-chain
   verification".

   **Offer a mise-driven dev container (opt-in).** Mention the optional `.devcontainer/` scaffold
   and set one up **only if the user wants it** — don't add Docker files unprompted. If they do,
   copy `references/templates/devcontainer/*` → `.devcontainer/` and adapt the `# KNOB:` markers
   for the detected stack: the base image (**match the project's prod image's Debian release** —
   invariant 1), the OS build deps, the accessory service(s), and the dep-install + DB step in
   `setup.sh`. Keep `setup.sh` executable in the git index
   (`git update-index --chmod=+x .devcontainer/setup.sh`), and copy `tasks.json.example` →
   `.vscode/tasks.json` if the project uses the dev-server/DB tasks. See "Dev container
   (mise-driven, advisory)" in `references/standard.md`.

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

6. **Repo ownership.** If the repo is the user's own, **commit** `mise.toml`/`hk.pkl`/`ci.yml`. If it
   is someone else's repo you only contribute to, do **not** commit them — add `hk.pkl` and
   `mise.toml` to `.git/info/exclude` instead. (This mirrors the dev-env-reminder hook's
   ownership rule.)

7. **Nudge env-to-fnox if secrets are in use.** If the checker reports `suggests_fnox=1` (the repo
   has a non-empty `.env`/`.env.local`, a Rails master key, or source references to credentials,
   and no `fnox.toml` yet), surface it in the final report: recommend running the [[env-to-fnox]]
   skill to migrate the plaintext secrets to fnox + Bitwarden Secrets Manager. Advisory only —
   don't auto-run it, and it never blocks compliance.

   Likewise, if the checker reports `devcontainer_mise_driven=0` (a `.devcontainer/` exists but has
   drifted from the mise toolchain — hardcoded base, nodesource, global pnpm, …), surface that in
   the report and offer to fix it per the v18 → v19 upgrade-guide steps. Advisory only — it never
   blocks compliance.

8. **Verify** (do this, don't assume):

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
   Confirm `mise.lock` is present and committed, that `.gitleaks.toml` is at the root
   (`has_gitleaks_config=1`), and that `README.md` + `CLAUDE.md` exist (`has_readme=1
   has_claude=1`). A good `.gitleaks.toml` smoke test: with a local `.env`/`log/` present,
   `hk run check` must still pass (no leaks found). Run the project's own tests too (`uv run
   pytest` / `bin/rails test` / `go test ./...`). Report real output.

   **If you scaffolded a dev container**, also verify it boots — don't assume:
   ```bash
   docker compose -f .devcontainer/compose.yaml build   # image builds
   # then run the postCreate inside the container, e.g.:
   docker compose -f .devcontainer/compose.yaml run --rm app .devcontainer/setup.sh
   # → mise install resolves the toolchain, deps install, the container comes up green
   bash "$CLAUDE_PLUGIN_ROOT/skills/dev-env-setup/scripts/dev_env_check.sh" .   # → devcontainer_mise_driven=1
   ```

## Fleet mode ("backfill all my repos after a bump")

A standard bump only matters once every tracking repo carries it — backfill the fleet right
after bumping, while the template changes are fresh. Mirror [[dependency-upgrade]]'s fleet
cadence, with the dev-env twists below:

1. **Enumerate live + confirm.** Run the roster script — never a remembered repo list (any
   memory of the fleet holds per-repo quirks at best; it is not the roster source):
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/skills/dev-env-setup/scripts/fleet_roster.sh"   # or: fleet_roster.sh ROOT ...
   ```
   It prints one line per `DEV_ENV_VERSION`-stamped repo — path, `version`, `branch`, `dirty`,
   `behind` — plus a summary. **Show the user the roster and confirm the target set before
   touching anything.**
2. **Ask disposition up front,** before upgrading anything: (a) which repos to **exclude**
   entirely; (b) what to do with **dirty repos** — the rule has varied round to round
   (upgrade-but-don't-commit-and-report one time, skip-entirely another), so ask, don't assume.
   And if the bump has plausible companion tooling (the actionlint-next-to-zizmor kind),
   **propose it now** — folding a second tool in after the fleet has been swept means a second
   sweep.
3. **Canary first.** Upgrade one repo by hand end-to-end (upgrade → verify → commit) before
   fanning out; a template bug or an environment gotcha caught on the canary costs one repo,
   not the whole fleet.
4. **Fan out one isolated agent per repo** (worktree isolation), each running the single-repo
   Workflow above: apply only the upgrade-guide sections **strictly newer** than that repo's
   `version`, verify (checker → `status=compliant`, `check_action_refs.sh`, run the changed
   command locally), commit with a consistent message, and push to the repo's **own default
   branch** — the roster's `branch=` field tells you; several repos are on `master`, not `main`.
5. **Report** one line per repo: upgraded / skipped / deferred, pushed (or left uncommitted,
   for the dirty-repo disposition that asks for it), and any deviation from the canary recipe.

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

From v16 every `uses:` is **pinned to a full commit SHA with the release tag in a trailing
comment** — `owner/repo@<40-hex-sha> # vX.Y.Z`. Tags are mutable, so an action takeover can
repoint `@v4` to malicious code that every downstream run picks up silently (tj-actions, Trivy);
a SHA can't be moved. The pins in `references/templates/ci.*.yml` are a snapshot and drift, so
**whenever you write or touch a workflow** (fresh setup *and* upgrade) bump every action to its
latest release SHA. See the **[[github-actions]]** skill for the full security checklist and the
fleet-wide bump.

The mechanical bump is `pinact` (install with `mise use -g pinact`): `pinact run` pins any
tag refs to SHAs with version comments, `pinact run -u` also updates pinned SHAs to the latest
release. Without pinact, resolve a single action by hand:

```bash
a=actions/checkout
tag=$(gh release view --repo "$a" --json tagName -q .tagName)   # e.g. v7.0.0
sha=$(gh api "repos/$a/commits/$tag" --jq .sha)                 # dereferences annotated tags
echo "uses: $a@$sha # $tag"
```

Do this for every action a repo uses. If `gh`/`pinact` is unavailable or unauthenticated, say
so and ask the user — never guess a SHA or a version.

**Always verify the pins before finishing.** The bundled checker resolves each pin's `# vX.Y.Z`
comment on the remote and fails if the tag is missing or its commit doesn't match the pinned
SHA (a lying / stale pin), and also flags any ref left as a mutable tag:

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/dev-env-setup/scripts/check_action_refs.sh" .github/workflows
# → "N ok, 0 unresolved" and exit 0; any FAIL line is a pin that lies or won't resolve.
```

(The `ci-action-ref-reminder` hook nudges you to run this whenever a workflow is edited.)

## Caching npm in CI

`actions/setup-node` ships a built-in npm cache (`with: { cache: npm }`) and the JS template
(`ci.js.yml`) uses it. But in a **polyglot repo where node is provisioned by mise**
(`jdx/mise-action`, so the workflow has *no* `setup-node` step), that cache isn't available —
every `npm ci` does a cold, network-bound install. Add an explicit cache, keyed on the
lockfile, to **each job that runs `npm ci`** (`setup-node`'s cache is per-job too, so the
fan-out is expected):

```yaml
- name: Cache npm downloads
  uses: actions/cache@v4
  with:
    path: ~/.npm  # npm's download cache — the same dir setup-node caches
    key: npm-${{ runner.os }}-${{ hashFiles('package-lock.json') }}
    restore-keys: npm-${{ runner.os }}-
```

Point `hashFiles` at the real lockfile — `package-lock.json` at the root, or
`frontend/package-lock.json` in a backend+frontend layout. Restoring `~/.npm` skips the
network on a warm key (`npm ci` still rebuilds `node_modules`, but from cache). Relatedly,
keep independent test suites in **separate jobs** (e.g. `backend-test` + `frontend-test`)
rather than one sequential job, so a failure in one suite doesn't short-circuit the run
before the other reports.

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
tracks latest on a 4-day cooldown floored at v5 (see the jscpd version-policy note in
`references/standard.md`). Project deps lock separately via `uv.lock` / `Gemfile.lock`.

**Tool-upgrade cooldown (v13):** `minimum_release_age = "4d"` in `[settings]` extends the 4-day
supply-chain window to `mise upgrade`. When re-resolving `"latest"`, mise only considers tool
versions published at least 4 days ago, giving the community time to catch and yank a malicious
release before it lands here. `mise install` is unaffected — it always reproduces the exact
version pinned in `mise.lock`.

## Dependency cooldown (supply-chain)

Hold off on freshly-published package versions for **4 days** before resolving them. Most malicious
releases (the 2026 Shai-Hulud npm waves, the axios / litellm incidents) are detected and yanked
within hours-to-days of publication, so a short cooldown means you are never the one who installs a
compromised version in the window before the community catches it. The standard already applies this
to its own tooling — the jscpd audit step resolves via `npx --before=<4 days ago>` (see the jscpd
version policy in `references/standard.md`) — and this section extends the same 4-day window to a
repo's own runtime / dev dependencies.

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

Only **uv** is checker-enforced for Python repos (see "The standard"); the rest are recommended
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

## gitleaks whole-tree allowlist (`.gitleaks.toml`)

The hk `gitleaks` step (`["gitleaks"] = Builtins.gitleaks`) runs `gitleaks dir`, which scans the
**entire working tree** — `dir` has no respect-gitignore flag, so it reads gitignored files too.
Without an allowlist, a local `.env`, `log/`, `tmp/cache/`, or a Rails
`config/credentials/*.key` makes the scan fail on those gitignored artifacts, blocking every
commit and keeping `hk run check` red (none of them are tracked, so CI — whose `gitleaks git`
job scans history — still passes, masking the problem).

`references/templates/.gitleaks.toml` is the fix: it `[extend]`s the default ruleset
(`useDefault = true`) and `[allowlist]`s the gitignored runtime/secret **paths** (`.env`, `log/`,
`tmp/`, `.venv/`, `node_modules/`, `vendor/`, `config/credentials/*.key`). gitleaks auto-loads
`.gitleaks.toml` from the scan root, so the hk builtin and CI's `gitleaks git` job both pick it
up with **no `--config` flag**. The allowlist is **path-scoped to gitignored locations only**, so
a secret hardcoded in `app/`/source is still caught.

**Caveat:** because CI's gitleaks job reads the same file, a secret force-added (`git add -f`)
into one of these paths wouldn't be caught by CI either. That's an accepted trade-off — the paths
are gitignored, so defeating it takes a deliberate `-f` against `.gitignore`. The complementary
path is to get the plaintext secret out of the repo entirely: when the checker detects secrets in
use without a `fnox.toml`, it emits `suggests_fnox=1` and the setup/upgrade report nudges the
[[env-to-fnox]] skill.

## Notes

- The version stamp is the single source of truth in `references/../VERSION`; the reminder hook
  reads the same file, so a repo on an older stamp gets flagged automatically.
- Never auto-run this from a hook — it's invoked by the user (or offered by the reminder), and it
  writes commit-tracked config, so confirm before committing.
- The standard ships **no `.gitignore` template** — Claude's defaults are usually right, but
  check the gotchas in [`references/standard.md`](references/standard.md) (".gitignore
  gotchas"): keep `.env` ignored AND allowlisted in `.gitleaks.toml`, commit lockfiles and
  `mise.toml`, keep `.venv/` ignored.
