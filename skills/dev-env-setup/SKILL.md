---
name: dev-env-setup
version: 1.0.0
description: |
  Audit a repo against Mick's dev-environment standard (mise pinning tools, an hk
  pre-commit hook running linters/tests + gitleaks, and a GitHub Actions workflow that
  mirrors those checks) and set it up or upgrade it. Use when a repo of Mick's is missing
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
  - AskUserQuestion
---

# dev-env-setup

Bring a repo up to **Mick's dev-environment standard** and keep it there. Reference
implementations: [`bedlam-bacs`], [`readoc`] (Python), [`booking-overview`] (Rails).

## The standard (v1)

A repo is **compliant at v1** when it has all of:

- **`mise.toml`** — `[tools]` pins `hk`, `pkl`, the stack tool (`uv` for Python), `gitleaks`,
  and (all stacks that run jscpd — Python, shell, **and Ruby/Rails**) `node` (to run jscpd via
  `npx`); `[env]` carries the version stamp `DEV_ENV_VERSION = "1"`.
- **`.jscpd.json`** (all stacks) — duplication config: `minTokens 70`, `threshold 0`,
  `reporters ["ai","threshold"]`, `gitignore true`.
- **`hk.pkl`** — amends a pinned hk `Config.pkl`, defines per-stack linter steps **plus
  `gitleaks` and `check-added-large-files`** (`Builtins.*`), and wires `pre-commit`
  (`fix = true`, `stash = "git"`), `fix`, and `check` hooks. The **`check` hook additionally
  runs the audits** (dead-code + duplication) — these are amended onto the `check` steps only,
  so they run in `hk run check` and CI but **not** on pre-commit.
- **`.github/workflows/ci.yml`** — runs the same lint + test + gitleaks checks, plus an
  `audit` job (dead-code + duplication + a large-file guard), on push/PR.

Per-stack checks (see `references/templates/`). **When each runs:** linters + large-file on
pre-commit; dead-code + duplication in `check`/CI only.
| Stack | Linters (pre-commit) | Tests | Secrets | Large file | Dead code (check/CI) | Duplication (check/CI) |
|-------|---------|-------|---------|------------|-----------|-------------|
| Python | `ruff check`, `ruff format` (via `uv run`) | `pytest` | gitleaks | `check-added-large-files` | `vulture` | `jscpd` |
| Ruby/Rails | `bin/rubocop` (omakase) | `bin/rails test` | gitleaks | `check-added-large-files` | `debride` | `jscpd` (polyglot gate) + `flay` (Ruby structural, advisory) |
| Shell / CC plugin | `shellcheck`, `shfmt`, `ruff` (any `.py`) | `pytest` over bundled scripts (see below) | gitleaks | `check-added-large-files` | `vulture` (any `.py`) | `jscpd` |

> Dead-code (`vulture`/`debride`) and duplication (`jscpd`/`flay`) are noisy by nature, so they
> live in the `check` hook + CI, never on pre-commit. Thresholds are tunable — see
> `references/upgrade-guide.md`.
>
> **jscpd** runs via `npx --yes jscpd@latest` (its v5 Rust engine ships through npm optional
> platform packages that `npx` resolves but the mise `npm:` backend doesn't), reading
> `.jscpd.json`. It uses the agent-friendly **`ai`** reporter (compact clone output) and the
> **`threshold`** reporter (CI gate). For extensionless **PEP 723** scripts (e.g. `bin/foo`),
> `vulture` also scans tracked files with a python/uv shebang; `ruff` needs them added to
> `[tool.ruff] extend-include`; jscpd keys off extensions, so duplication on extensionless
> scripts isn't auto-covered. To auto-fix clones, agents can run
> `npx skills add https://github.com/kucherenko/jscpd --skill dry-refactoring`.

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
   Adjust specifics (default branch name, Python version, extra source globs for extensionless
   CLIs like `bin/foo` — add them to `hk.pkl` globs and `[tool.ruff] extend-include`). The templates
   already include `DEV_ENV_VERSION`, gitleaks, and the audit checks. **Add the audit deps**
   the templates assume: `vulture` to the Python dev group; `flay` + `debride` to the Ruby
   Gemfile dev group (mise pulls `node` for jscpd, which runs via `npx`, on all jscpd stacks
   incl. Ruby). **For a
   shell/plugin repo**, also add the [`readoc`]-style dev project (`pyproject.plugin.toml` →
   `pyproject.toml`, fill in the name) and a `tests/` suite (`test_scripts.example.py` as a
   starting point) so every bundled script is exercised, and give each Python script the
   `uv run --script` shebang + PEP 723 block. **Before writing the workflow, pin every GitHub
   Action to its current latest version** — the template versions are a snapshot and go stale.
   See "Keeping GitHub Actions current".

4. **Upgrade — apply the guide.** Read [`references/upgrade-guide.md`](references/upgrade-guide.md)
   and apply every section **strictly newer** than `repo_version`, in order. Then set
   `DEV_ENV_VERSION` in `mise.toml` to `current_version`. (Existing v0 repos — hk/mise/CI that
   predate this standard — add the stamp + gitleaks + large-file + the dead-code/duplication
   audits per the v0 → v1 section.) **Also audit the existing workflow's Actions** and bump any
   that are behind latest (same recipe below).

5. **Repo ownership.** If the repo is Mick's, **commit** `mise.toml`/`hk.pkl`/`ci.yml`. If it
   is someone else's repo you only contribute to, do **not** commit them — add `hk.pkl` and
   `mise.toml` to `.git/info/exclude` instead. (This mirrors the dev-env-reminder hook's
   ownership rule.)

6. **Verify** (do this, don't assume):
   ```bash
   mise install            # provision hk, pkl, gitleaks, etc.
   hk install              # install the git hooks
   hk run check            # all steps, including gitleaks, must pass
   bash "$CLAUDE_PLUGIN_ROOT/skills/dev-env-setup/scripts/dev_env_check.sh" .   # → status=compliant
   ```
   Run the project's own tests too (`uv run pytest` / `bin/rails test`). Report real output.

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
`actions/upload-artifact`, `gitleaks/gitleaks-action` — and any others a repo already uses.
When upgrading an existing repo, list each Action with its current vs. latest version and bump
the stale ones in the same pass. If `gh` is unavailable or unauthenticated, say so and ask Mick
to check, rather than guessing a version.

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
- **Commit lockfiles, don't ignore them** (`uv.lock`, `Gemfile.lock`). The standard pins tools
  for reproducibility; a library-flavored default that drops lockfiles defeats that.
- **`mise.local.toml` is the ignorable one; `mise.toml` is committed** — the `DEV_ENV_VERSION`
  stamp lives in the committed file, machine-local overrides go in `mise.local.toml`.
- **Keep `.venv/` ignored** — CI's `git ls-files` and `.jscpd.json`'s `ignore` both assume it.
  The default already covers this; just don't un-ignore it.

[`bedlam-bacs`]: https://github.com/EdinburghUniversityTheatreCompany/bacs-tool
[`readoc`]: https://github.com/mickzijdel/readoc
[`booking-overview`]: https://github.com/mickzijdel/booking-overview
