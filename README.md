# dev-hooks

A Claude Code plugin bundling eleven polyglot, project-agnostic dev-workflow hooks plus a
set of thinking-tool skills. Each hook script detects the project's own toolchain
(Ruby/Rails, JavaScript/TypeScript, Python) — there is nothing to configure.

## What's included

| Event | Script | Purpose |
|-------|--------|---------|
| `PostToolUse` (`Write`\|`Edit`) | `lint-on-edit.sh` | Auto-fix/format the file Claude just wrote using the linter **this** project configures (RuboCop/Standard, erb_lint, Biome/Prettier/ESLint, Ruff/Black). Safe fixes only, never blocks. |
| `PostToolUse` (`Write`\|`Edit`) | `latest-deps-reminder.sh` | When Claude writes a dependency manifest (`requirements.txt`, `package.json`, `Gemfile`, `pyproject.toml`, …) or hand-writes a lockfile, remind it to verify the versions are **current** (training data goes stale) with the right lookup command per ecosystem, or to regenerate lockfiles via the package manager. On manifest edits it also nudges Claude to keep the README/CLAUDE.md key-package versions in sync (creating those docs if missing). Advisory only, never blocks; fires once per session per ecosystem. |
| `PostToolUse` (`Write`\|`Edit`) | `dockerfile-reminder.sh` | When Claude writes a `Dockerfile`/`Containerfile`, run **hadolint** on it and feed the findings (or a clean pass) back to Claude, plus a layer-ordering nudge that points at the `dockerfile` skill. If hadolint isn't installed, falls back to a once-per-session ordering/gotchas reminder. Advisory only — reports every time, never blocks. |
| `PostToolUse` (`Write`\|`Edit`) | `secret-plaintext-reminder.sh` | When Claude writes what looks like a plaintext secret **value** (a named `API_KEY`/`SECRET`/`TOKEN`/`PASSWORD` assignment to a real literal, a private-key block, or an AWS key id), nudge it to migrate to fnox via the `env-to-fnox` skill instead of committing the value. Fires at write time (before `gitleaks` would at commit). Env-var refs and obvious placeholders are ignored. Advisory only, never blocks; fires once per session. |
| `PostToolUse` (`Write`\|`Edit`) | `popover-reminder.sh` | When Claude writes popover/tooltip/dropdown/menu UI (a frontend file — `.js`/`.ts`/`.erb`/`.html`/`.vue`/`.svelte`/`.haml`/`.slim` — that has a popover/tooltip/dropdown controller filename, `role="tooltip"`/the `popover` attribute, an `@floating-ui`/`popper`/`tippy` import, a `data-controller` naming one, or a tooltip/popover/dropdown class/data-attribute), nudge it to use a collision-aware positioner (flip + shift) rendered in the top layer/a portal instead of hand-rolled `top`/`left` math, and point at the `popovers-tooltips` skill. Advisory only, never blocks; fires once per session. Opt out with `DEV_HOOKS_POPOVER=false`. |
| `PostToolUse` (`Write`\|`Edit`) | `ci-action-ref-reminder.sh` | When Claude writes/edits a GitHub Actions workflow (a `*.yml`/`*.yaml` pinning `uses: owner/repo@ref`), nudge it to verify every ref actually **resolves on the remote** before finishing — an action can ship release tags (`v8.0.0`) without floating a `@v8` major, so a wrong pin passes locally but breaks CI at "Prepare all required actions". Points Claude at the bundled `check_action_refs.sh` (which does the `git ls-remote` check); the hook itself never hits the network. Advisory only, never blocks; fires once per session per file. |
| `Stop` | `verify-work.sh` | On stop, detect changed code files and run the project's linters/tests (RuboCop, Minitest/RSpec, Ruff/pytest, ESLint/JS tests). Feeds failures back to Claude (exit 2) so it fixes them before finishing. |
| `Stop` | `debug-leftover-reminder.sh` | On stop, flag debug statements Claude **newly introduced** this session (`console.log`/`debugger`, `binding.pry`/`byebug`/Ruby `p`, `breakpoint()`/`pdb`) — diffed against `HEAD` so pre-existing lines are ignored — and feed them back (exit 2) to strip before finishing. Test files excluded. Fires at most once per session. |
| `Stop` | `missing-test-reminder.sh` | On stop, if Claude **added** a new source file this session with no matching test (`*_spec.rb`/`*_test.rb`, `test_*.py`/`*_test.py`, `*.test.*`/`*.spec.*`), nudge it (exit 2) to add one. Skips test files, low-value targets (barrels, type defs, config, migrations, `__init__`/`conftest`), and vendored/generated code (dirs from the repo's `.jscpd.json`, plus minified `*.min.*`). Fires at most once per session. |
| `SessionStart` | `detect-stack-skills.sh` | Detect the project's stack and remind Claude to consult applicable skills/conventions before writing code. |
| `SessionStart` | `dev-env-reminder.sh` | If the repo is **yours** and the dev-env standard applies but isn't met (missing `mise`/`hk`/CI/`gitleaks`, or behind the version stamp), nudge Claude to flag it and offer the `dev-env-setup` skill. Advisory only — never edits. Owner-gated (see env vars below); opt out per repo. |
| `Stop` | `plan-reminder.sh` | If `.claude/current_plan.md` exists and is stale, remind Claude to update the multi-session plan before ending. |
| `Stop` | `review-reminder.sh` | On stop, if code files changed but no code review ran this session (scans the transcript for `/code-review`, the code-reviewer agent, or `requesting-code-review`), remind Claude (exit 2) to run a review and keep iterating until it comes back clean. Fires at most once per session. |
| `Stop` | `memory-reminder.sh` | On stop of a substantial session (≥ 6 human turns), remind Claude (exit 2) to capture durable, non-obvious learnings into its file-based memory — memory dir only, never CLAUDE.md, with an explicit "nothing worth saving" escape hatch. Fires at most once per session. Opt-in via `DEV_HOOKS_MEMORY=1`, or auto-enabled once you use Claude's memory feature anywhere. |

## Skills

On-demand "thinking tools" and writing/content helpers you invoke as slash commands (or that I
reach for when the trigger fits). The first group are critique/decision/automation workflows
distilled from the `#ai-productivity-digest` tips; the second group are writing/content and
secrets-workflow helpers adapted from [Nate Berkopec's dotfiles](https://github.com/nateberkopec/dotfiles).

| Skill | Use when |
|-------|----------|
| `but-for-real` | About to claim something is done/fixed/working — forces re-reading the real code, running it, and separating verified from assumed. |
| `premortem` | Before committing to a non-trivial plan — imagines it already failed and works backward to failure modes, hidden assumptions, and a revised plan. |
| `board` | You want hard, independent critique — convenes a panel of real parallel advisor subagents, then a chairman synthesizes. |
| `self-rate` | Before returning uncertain work — scores it on a calibrated scale, then tightens overclaims to match. |
| `weekly-automation-review` | Weekly cadence — reviews recent activity and recommends 1–2 repetitive tasks to automate; runs as a scheduled Monday remote agent. |
| `commit-digest` | Weekly cadence — reviews recent commits in tracked external repos (+ optional Atom/RSS feeds), pulls applicable improvements in as separate PRs, and logs every skipped suggestion to the `claude/skipped-log` branch with dedup and a per-run PR comment. Companion to `weekly-automation-review`, which reviews the local repo's own activity. |
| `dev-env-setup` | Auditing/setting up a repo against my dev-env standard, version-tracked via `DEV_ENV_VERSION`: mise pinning the toolchain, an hk pre-commit hook running linters/tests + gitleaks, a CI workflow mirroring those checks, a 4-day dependency cooldown (uv `exclude-newer` enforced on Python repos; Ruby/JS package managers documented), and project docs — a `README.md` and `CLAUDE.md` recording the project's pinned key-package versions, dispatching a subagent to create them when missing. Paired with the `dev-env-reminder` hook; trimmed from Nate Berkopec's `dev-env-setup` (kept/dropped rationale in the skill; per-version migration steps in `references/upgrade-guide.md`). |
| `dockerfile` | Writing/editing a Dockerfile — cache-friendly layer ordering (least→most frequently changed) and common gotchas (pinning, multi-stage, `.dockerignore`, non-root, exec-form `CMD`). Paired with the `dockerfile-reminder` hook; delegates linting to `hadolint`. |
| `popovers-tooltips` | Building/fixing popovers, tooltips, dropdowns or menus that open off-screen or get clipped — Tailwind styles but doesn't position; use a collision-aware positioner (flip + shift) + top-layer/portal. Rails/Hotwire-first: Floating UI (`@floating-ui/dom`) in a Stimulus controller with `autoUpdate` and `disconnect()` cleanup (the Turbo gotcha), plus Tippy/Flowbite/Preline and the native Popover API. Paired with the `popover-reminder` hook. |
| `github-readme` | Creating/revising a GitHub README — section order, onboarding flow, runnable quickstart, plus an audit script and advanced GFM features. |
| `humanizer` | Removing tells of AI-generated writing — em-dash overuse, rule-of-three, promotional tone, etc. (based on Wikipedia's "Signs of AI writing"). |
| `readability` | Making web copy scannable — inverted pyramid, plain language, plus Flesch-Kincaid/vocabulary audit scripts. |
| `env-to-fnox` | Migrating a project's plaintext `.env` to [fnox](https://fnox.jdx.dev) — references in a committed `fnox.toml`, real values in a vault (defaults to Bitwarden Secrets Manager). |

> `github-readme`, `humanizer`, and `readability` are adapted **verbatim** from
> [Nate Berkopec's dotfiles](https://github.com/nateberkopec/dotfiles) (credit to Nate; each
> `SKILL.md` links back to its source). `env-to-fnox` is adapted from the same source with the
> provider switched from 1Password to Bitwarden. `humanizer` is additionally based on
> [Wikipedia: Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing)
> (WikiProject AI Cleanup).

## Install

Direct from GitHub:

```bash
/plugin install github:mickzijdel/dev-hooks
```

Or via the bundled marketplace:

```bash
/plugin marketplace add mickzijdel/dev-hooks
/plugin install dev-hooks@dev-hooks
```

## Local development

This repo doubles as a "skills-directory plugin": symlink it into `~/.claude/skills/` and
it auto-loads (run `/reload-plugins` to pick up changes).

```bash
ln -s ~/Stack/Programmeren/dev-hooks ~/.claude/skills/dev-hooks
```

> ⚠️ Do **not** symlink AND marketplace-install on the same machine — the hooks would
> fire twice. Use the symlink on your dev machine and the marketplace install elsewhere.

## Notes

- `verify-work.sh` only runs inside a git repo and only when relevant code files have
  changed; it no-ops otherwise.
- `dev-env-reminder.sh` only nudges on repos it judges **yours** and only when the standard
  applies but isn't met; it's advisory and never edits anything. Ownership = origin remote
  owner in an allowlist (default `mickzijdel`) **or** ≥80% of the last month's commits are
  yours. Tune/override via env (set in `.claude/settings.local.json` `"env"`):
  `DEV_HOOKS_DEVENV_OWNED` (`true`/`false` — deterministic per-repo override, `false` silences
  it entirely), `DEV_HOOKS_DEVENV_OWNERS` (extra GitHub owners, e.g.
  `EdinburghUniversityTheatreCompany`), `DEV_HOOKS_DEVENV_EMAIL` (default `mickzijdel@live.nl`).
  Per-repo opt-out also via a `dev-env: skip` line in the project's `CLAUDE.md`.
- `memory-reminder.sh` targets Claude Code's file-based memory feature. It stays a no-op
  unless you set `DEV_HOOKS_MEMORY=1` or have already used memory somewhere (it detects any
  existing `~/.claude/projects/*/memory/` dir), so it's safe for installers who don't use
  memory. It only nudges Claude to capture learnings — it never writes memory or edits
  CLAUDE.md itself, and Claude is told to save nothing when there's nothing durable.
- `latest-deps-reminder.sh` is reminder-only — it never queries a package registry, just
  nudges Claude to look up current versions itself (training data goes stale). On manifest
  edits (python/js/ruby — not lockfiles) it additionally reminds Claude to keep README.md
  and CLAUDE.md key-package versions in sync, creating those docs if they don't exist. It
  fires at most once per session per ecosystem (python/js/ruby/lockfile), tracked via a
  marker under `${TMPDIR:-/tmp}/dev-hooks-latest-deps/`. Silence it with
  `DEV_HOOKS_LATEST_DEPS=false` (in `.claude/settings.local.json` `"env"`).
- `dockerfile-reminder.sh` runs [`hadolint`](https://github.com/hadolint/hadolint) on each
  `Dockerfile`/`Containerfile` Claude writes and reports the findings (or a clean pass) back
  to Claude, plus a layer-ordering nudge pointing at the `dockerfile` skill. It's report-only:
  it surfaces results every time but never blocks the write — Claude decides whether to fix.
  If `hadolint` isn't installed it can't lint, so it falls back to a once-per-session
  ordering/gotchas reminder (tracked via a marker under `${TMPDIR:-/tmp}/dev-hooks-dockerfile/`)
  and suggests installing hadolint. Silence the whole hook with `DEV_HOOKS_DOCKERFILE=false`
  (in `.claude/settings.local.json` `"env"`).
- `popover-reminder.sh` is reminder-only — it never blocks the write. It fires when Claude
  writes a frontend file (`.js`/`.ts`/`.jsx`/`.tsx`/`.mjs`/`.vue`/`.svelte`/`.erb`/`.html`/
  `.haml`/`.slim`) carrying a popover/tooltip signal: a popover/tooltip/dropdown/popper/floating
  controller filename, `role="tooltip"`/the native `popover` attribute/`popovertarget`, an
  `@floating-ui`/`popper`/`tippy` import, a `data-controller` naming one, or a
  tooltip/popover/dropdown `class`/`data-*` attribute (matching is deliberately broad). It nudges
  Claude to use a collision-aware positioner (flip + shift) rendered in the top layer/a portal —
  not hand-rolled `top`/`left` math that opens off-screen — and points at the `popovers-tooltips`
  skill (Floating UI in a Stimulus controller for Rails/Hotwire). Fires once per session, tracked
  via a marker under `${TMPDIR:-/tmp}/dev-hooks-popover/`. Silence it with `DEV_HOOKS_POPOVER=false`
  (in `.claude/settings.local.json` `"env"`).
- `secret-plaintext-reminder.sh` is reminder-only — it never blocks the write and never reads
  anything beyond the content Claude just wrote. Detection is deliberately conservative
  (named `KEY`/`SECRET`/`TOKEN`/`PASSWORD`-style assignments to a real literal, private-key
  blocks, AWS key ids); env-var references (`process.env`, `os.environ`, `${VAR}`) and obvious
  placeholders are ignored, and `*.example`/`*.sample`/`*.template`/`fnox.toml`/lockfiles are
  skipped. It fires at write time (before `gitleaks` would at commit) and points at the
  `env-to-fnox` skill. Fires once per session, tracked via a marker under
  `${TMPDIR:-/tmp}/dev-hooks-secrets/`. Silence it with `DEV_HOOKS_SECRETS=false` (in
  `.claude/settings.local.json` `"env"`).
- `ci-action-ref-reminder.sh` is reminder-only — it never hits the network. It fires when
  Claude writes a `*.yml`/`*.yaml` that pins a remote action (`uses: owner/repo@ref`) and points
  Claude at the bundled `skills/dev-env-setup/scripts/check_action_refs.sh`, which does the
  actual `git ls-remote` resolution and exits non-zero on any unresolved ref. That script
  classifies each ref as `OK`/`FAIL`/`PIN` (commit SHA)/`SKIP` (remote unreachable — never a
  failure), so offline runs don't false-alarm; you can also run it directly over a workflow or
  `.github/workflows`. Fires once per session per file (marker under
  `${TMPDIR:-/tmp}/dev-hooks-ci-action-refs/`). Silence it with `DEV_HOOKS_CI_ACTION_REFS=false`
  (in `.claude/settings.local.json` `"env"`).
- `debug-leftover-reminder.sh` only considers **newly-introduced** lines (added lines in
  `git diff HEAD` plus the full contents of untracked files), so committed/pre-existing debug
  statements are ignored — committing or removing the lines clears the nudge. It runs only in
  a git repo, excludes test files, and fires at most once per session (its sentinel in the
  transcript suppresses a re-fire). Silence it with `DEV_HOOKS_DEBUG_LEFTOVER=false` (in
  `.claude/settings.local.json` `"env"`).
- `missing-test-reminder.sh` only looks at files **newly added** this session (untracked or
  staged-added), excludes test files, low-value targets (barrels, type defs, `*.config.*`,
  migrations, `__init__.py`/`conftest.py`), and vendored/generated code, and stays silent if a
  matching test already exists anywhere in the tree. Vendored/generated dirs come from the repo's
  own `.jscpd.json` `ignore` globs at run time (falling back to a built-in default —
  `node_modules`, `vendor`, `dist`, `build`, `app/assets/builds` — when the repo has no
  `.jscpd.json`); minified files (`*.min.js` etc.) are always skipped. Runs only in a git repo;
  fires once per session (transcript sentinel).
  It can false-positive on files that legitimately need no test — Claude is told to say so and
  move on. Silence it with `DEV_HOOKS_MISSING_TEST=false` (in `.claude/settings.local.json`
  `"env"`).
- Hooks require `jq` (used to parse hook input) and, for `verify-work.sh`, `memory-reminder.sh`,
  `debug-leftover-reminder.sh`, and `missing-test-reminder.sh`, `python3`.
- The `github-readme` and `readability` skills bundle optional Python audit scripts
  (`scripts/*.py`, self-contained via [uv](https://docs.astral.sh/uv/) + PEP 723 inline
  metadata — run with `uv run scripts/<name>.py`); they only run when you invoke the skill
  and ask for the audit.
- The `dev-env-setup` skill applies a [mise](https://mise.jdx.dev)/[hk](https://hk.jdx.dev)
  standard, so the repos it sets up depend on `mise`, `hk`, `pkl`, `gitleaks` (and
  `shellcheck`/`shfmt` for shell repos) — all provisioned via the generated `mise.toml`. The
  `dev-env-reminder` hook itself only needs `git`, `jq`, and `bash`.
