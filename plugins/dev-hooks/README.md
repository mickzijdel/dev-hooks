# dev-hooks

A Claude Code plugin bundling polyglot, project-agnostic dev-workflow hooks plus the
companion skills the hooks point at. Each hook script detects the project's own toolchain
(Ruby/Rails, JavaScript/TypeScript, Python) — there is nothing to configure.

Part of the [dev-hooks marketplace](../../README.md), alongside `coding-onboarding`,
`thinking-tools`, and `writing`.

## Contents

- [Hooks](#hooks)
- [Skills](#skills)
- [Install](#install)
- [Usage](#usage)
- [Notes](#notes)
- [License](#license)

## Hooks

| Event | Script | Purpose |
|-------|--------|-------|
| `UserPromptSubmit` | `prompt-log.sh` | Append one JSON line per user prompt (timestamp, repo cwd, session id, prompt length, first 500 chars) to `~/.claude/automation-review/prompts.jsonl` — the cross-repo data source the `thinking-tools` `weekly-automation-review` skill clusters to spot repetitive requests worth automating. Local-only, silent, never blocks the prompt. Opt out with `DEV_HOOKS_PROMPT_LOG=false`. |
| `PreToolUse` (`Bash`) | `dangerous-command-guard.sh` | Inspect the bash command about to run and gate the genuinely dangerous ones: **deny** the catastrophic, irreversible few (wipe the disk/home, fork bomb, format/overwrite a block device, `chmod -R 777 /`) and **ask** (force a human confirmation, with a plain-language reason) on risky-but-legitimate ones (`rm -rf` a path, `git reset --hard`/`clean -f`/`checkout .`, force-push, `curl … \| bash`, `sudo`). Flags and targets are judged per simple command, so `cd ~ && rm -rf build/` isn't read as `rm -rf ~`. Everything else passes straight through to the normal permission flow. Aimed at beginners whose agents shouldn't run an irreversible command on their say-so. Opt-in extra (`DEV_HOOKS_GUARD_MAIN=1`, seeded by the `coding-onboarding` plugin's `getting-started` skill): ask before committing/pushing straight to `main`/`master`. Opt out with `DEV_HOOKS_BASH_GUARD=false`. |
| `PostToolUse` (`Write`\|`Edit`\|`MultiEdit`) | `lint-on-edit.sh` | Auto-fix/format the file Claude just wrote using the linter **this** project configures (RuboCop/Standard, herb/erb_lint for ERB, Biome/Prettier/ESLint, Ruff/Black). Safe fixes only, never blocks. |
| `PostToolUse` (`Write`\|`Edit`\|`MultiEdit`) | `latest-deps-reminder.sh` | When Claude writes a dependency manifest (`requirements.txt`, `package.json`, `Gemfile`, `pyproject.toml`, …) or hand-writes a lockfile, remind it to verify the versions are **current** (training data goes stale) with the right lookup command per ecosystem, or to regenerate lockfiles via the package manager. On manifest edits it also nudges Claude to keep the README/CLAUDE.md key-package versions in sync (creating those docs if missing). Advisory only, never blocks; fires once per session per ecosystem. |
| `PostToolUse` (`Write`\|`Edit`\|`MultiEdit`) | `scaffold-reminder.sh` | When Claude **creates a new** project manifest or framework entrypoint by hand (`Gemfile`, `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `mix.exs`, `composer.json`, `build.gradle`/`pom.xml`, `manage.py`, `config/application.rb`, …), remind it to run the framework's official generator (`rails new`, `npm create vite@latest`, `django-admin startproject`, `cargo new`, …) instead of scaffolding from memory — and to check the framework's current stable release and the generator's current flags first, unless the user pinned a version. Write-tool only; files git already tracks are skipped. Advisory only, never blocks; fires once per session. Opt out with `DEV_HOOKS_SCAFFOLD=false`. |
| `PostToolUse` (`Write`\|`Edit`\|`MultiEdit`) | `dockerfile-reminder.sh` | When Claude writes a `Dockerfile`/`Containerfile`, run **hadolint** on it and feed the findings (or a clean pass) back to Claude, plus a layer-ordering nudge that points at the `dockerfile` skill. If hadolint isn't installed, falls back to a once-per-session ordering/gotchas reminder. Advisory only — reports every time, never blocks. |
| `PostToolUse` (`Write`\|`Edit`\|`MultiEdit`) | `secret-plaintext-reminder.sh` | When Claude writes what looks like a plaintext secret **value** (a named `API_KEY`/`SECRET`/`TOKEN`/`PASSWORD` assignment to a real literal, a private-key block, or an AWS key id), nudge it to migrate to fnox via the `env-to-fnox` skill instead of committing the value. Fires at write time (before `gitleaks` would at commit). Env-var refs and obvious placeholders are ignored. Advisory only, never blocks; fires once per session. |
| `PostToolUse` (`Write`\|`Edit`\|`MultiEdit`) | `popover-reminder.sh` | When Claude writes popover/tooltip/dropdown/menu UI (a frontend file — the shared extension list, see `inline-svg-reminder.sh` notes — that has a popover/tooltip/dropdown controller filename, `role="tooltip"`/the `popover` attribute, an `@floating-ui`/`popper`/`tippy` import, a `data-controller` naming one, or a tooltip/popover/dropdown class/data-attribute), nudge it to use a collision-aware positioner (flip + shift) rendered in the top layer/a portal instead of hand-rolled `top`/`left` math, and point at the `popovers-tooltips` skill. Advisory only, never blocks; fires once per session. Opt out with `DEV_HOOKS_POPOVER=false`. |
| `PostToolUse` (`Write`\|`Edit`\|`MultiEdit`) | `ci-action-ref-reminder.sh` | When Claude writes/edits a GitHub Actions workflow (a `*.yml`/`*.yaml` pinning `uses: owner/repo@ref`), point it at the `github-actions` skill's supply-chain checklist (**SHA-pin** every action, read-only `GITHUB_TOKEN`, no untrusted input in `run:`) and have it verify the pins with the bundled `check_action_refs.sh` (which resolves each pin's `# vX.Y.Z` comment via `git ls-remote` and fails on a missing/mismatched tag); the hook itself never hits the network. Advisory only, never blocks; fires once per session per file. |
| `PostToolUse` (`Write`\|`Edit`\|`MultiEdit`) | `inline-svg-reminder.sh` | When Claude hand-writes **inline SVG** into a frontend file (an `<svg>` blob with real drawing content — `<path>`/`<circle>`/`<rect>`/… or long `d="M…"` path data — or a `data:image/svg+xml` URI), feed a correction back (exit 2, **every occurrence**): use the project's icon library (named from `package.json`/`Gemfile` when found), else extract to a dedicated `.svg` file/sprite and reference it. Good patterns stay silent: `<use href>` sprite refs, writing `.svg` files, `<img src="x.svg">`, markdown, test files, data-driven chart markup (`<rect x={…}>`), and pre-existing SVG (Writes deduped against `HEAD`, Edits against `old_string`). Opt out with `DEV_HOOKS_SVG_INLINE=false`. |
| `PostToolUse` (`Write`\|`Edit`\|`MultiEdit`) | `migration-safety-reminder.sh` | When Claude writes a database migration (Rails `db/migrate/*.rb`, Django `<app>/migrations/*.py`, Alembic `…/versions/*.py`), nudge it to check safe-migration practice — reversibility (`change`/`up`+`down`/`downgrade`), no data backfill inside a schema migration, lock-safe column adds (nullable → batched backfill → constraint), and concurrent index creation (`algorithm: :concurrently` + `disable_ddl_transaction!`, `CREATE INDEX CONCURRENTLY`, `AddIndexConcurrently`). Advisory only, never blocks; fires once per session. Opt out with `DEV_HOOKS_MIGRATION=false`. |
| `PostToolUse` (`Write`\|`Edit`\|`MultiEdit`) | `a11y-reminder.sh` | When Claude writes frontend markup with common accessibility gaps — an `<img>` with no `alt`, an icon-only `<button>`/`<a>` with no accessible name, a click handler on a non-interactive `<div>`/`<span>`, or an unlabeled form `<input>` — flag them and point at the `accessibility` skill. Scans only what the call adds; heuristic. Advisory only, never blocks; fires once per session. Opt out with `DEV_HOOKS_A11Y=false`. |
| `PostToolUse` (`Write`\|`Edit`\|`MultiEdit`) | `sql-injection-reminder.sh` | When Claude writes SQL with a value interpolated straight into the query string (a Python f-string, Ruby `#{}`, or string concatenation around SQL keywords), nudge it toward parameterized queries / ORM bind variables. The safe `%s`/`:name`/`?` placeholder styles are not flagged. Advisory only, never blocks; fires once per session. Opt out with `DEV_HOOKS_SQL_INJECTION=false`. |
| `PostToolUse` (`Write`\|`Edit`\|`MultiEdit`) | `error-swallow-reminder.sh` | When Claude writes a handler that silently swallows the error (a Python bare `except:` or `except …: pass`, an empty JS/TS `catch {}`, or an empty Ruby `rescue … end`), nudge it to catch the specific exception and handle/log/re-raise instead. Scans only what the call adds. Advisory only, never blocks; fires once per session. Opt out with `DEV_HOOKS_ERROR_SWALLOW=false`. |
| `Stop` | `verify-work.sh` | On stop, detect changed code files and run the project's linters/tests (RuboCop, herb + brakeman for Rails, Minitest/RSpec, Ruff/pytest, ESLint/JS tests). Feeds failures back to Claude (exit 2) so it fixes them before finishing. When [rtk](https://github.com/rtk-ai/rtk) is on PATH, the **test** runs go through `rtk test` (keeps failures, drops passing-test noise, propagates the exit code) to shrink the feedback; linters stay raw. Falls back to bare commands without rtk. Opt out of the rtk wrapping with `DEV_HOOKS_VERIFY_RTK=false`. (If you install rtk via mise and also enable its own global rewrite hook with `rtk init`, point that hook at the real binary — e.g. `~/.local/share/mise/installs/rtk/latest/rtk hook claude` — not the bare `rtk` shim, which Claude Code's stripped hook PATH can't resolve, so it silently no-ops.) |
| `Stop` | `debug-leftover-reminder.sh` | On stop, flag debug statements Claude **newly introduced** this session (`console.log`/`debugger`, `binding.pry`/`byebug`/Ruby `p`, `breakpoint()`/`pdb`) — diffed against `HEAD` so pre-existing lines are ignored — and feed them back (exit 2) to strip before finishing. Test files excluded. Fires at most once per session. |
| `Stop` | `todo-leftover-reminder.sh` | On stop, list `TODO`/`FIXME`/`XXX`/`HACK` markers Claude **newly introduced** this session (diffed against `HEAD` so pre-existing markers are ignored; test files excluded) and feed them back (exit 2) to resolve before finishing. Fires at most once per session. Opt out with `DEV_HOOKS_TODO_LEFTOVER=false`. |
| `Stop` | `missing-test-reminder.sh` | On stop, if Claude **added** a new source file this session with no matching test (`*_spec.rb`/`*_test.rb`, `test_*.py`/`*_test.py`, `*.test.*`/`*.spec.*`), nudge it (exit 2) to add one. Skips test files, low-value targets (barrels, type defs, config, migrations, `__init__`/`conftest`), and vendored/generated code (dirs from the repo's `.jscpd.json`, plus minified `*.min.*`). Fires at most once per session. |
| `SessionStart` | `detect-stack-skills.sh` | Detect the project's stack and remind Claude to consult applicable skills/conventions before writing code. |
| `SessionStart` | `dev-env-reminder.sh` | If the repo is **yours** and the dev-env standard applies but isn't met (missing `mise`/`hk`/CI/`gitleaks`, or behind the version stamp), nudge Claude to flag it and offer the `dev-env-setup` skill. Advisory only — never edits. Owner-gated (see env vars below); opt out per repo. |
| `SessionStart` | `docs-context.sh` | If the project has a `docs/` or `doc/` directory containing Markdown files, emit a brief index (titles + optional descriptions from YAML frontmatter) so Claude knows where documentation lives and can consult the right files when working on related features. Advisory only — never blocks. Opt out with `DEV_HOOKS_DOCS_CONTEXT=false`. |
| `SessionStart` | `script-index.sh` | List the custom CLI tools in your saved script library — each executable shebang script's path + its `# short-description:` line — so Claude knows what already exists and reaches for it instead of re-solving the problem, like a lightweight skill index. The library is `DEV_HOOKS_SCRIPT_DIR`, a colon-separated list of roots like `PATH` (default `~/.local/bin`), each scanned **recursively** so a cloned scripts repo with subdirectories works. Scripts with no `# short-description:` are listed under a placeholder telling Claude to run `<path> --help` and ask you to add one. Hide scripts that aren't your own tools (installed/third-party CLIs, app launchers) with `DEV_HOOKS_SCRIPT_IGNORE` — a colon-separated list of globs matched against each script's basename or full path (e.g. `*vocalinux*:gext`). Never executes a script (so no `--help` side effects at startup). Paired with the `script-library` skill. Advisory only — never blocks. Opt out with `DEV_HOOKS_SCRIPT_INDEX=false`. |
| `Stop` | `plan-reminder.sh` | If `.claude/current_plan.md` exists and is stale, remind Claude to update the multi-session plan before ending. |
| `Stop` | `review-reminder.sh` | On stop, if code files changed but no code review ran this session (scans the transcript for `/code-review`, the code-reviewer agent, or `requesting-code-review`), remind Claude (exit 2) to run a review and keep iterating until it comes back clean. Fires at most once per session. |
| `Stop` | `compress-comments-reminder.sh` | On stop, if the session's diff added a noticeable number of comment lines to code files (≥ 3, counting `git diff HEAD` added lines plus untracked code files; shebangs and directive comments like `shellcheck`/`noqa`/`eslint` don't count), remind Claude (exit 2) to run the `compress-comments` skill — delete comments that restate the code, compress the rest. Fires at most once per session; running the skill (or a prior reminder) suppresses it. Opt out with `DEV_HOOKS_COMPRESS_COMMENTS=false`. |
| `Stop` | `memory-reminder.sh` | On stop of a substantial session (≥ 6 human turns), remind Claude (exit 2) to capture durable, non-obvious learnings into its file-based memory — memory dir only, never CLAUDE.md, with an explicit "nothing worth saving" escape hatch. Fires at most once per session. Opt-in via `DEV_HOOKS_MEMORY=1`, or auto-enabled once you use Claude's memory feature anywhere. |
| `Stop` | `big-change-reminder.sh` | On stop, if the working tree holds a very large **uncommitted** change (default: ≥ 25 files or ≥ 800 added lines), nudge Claude (exit 2) to slow down — commit the working pieces in small, focused commits, run tests, get a review, and consider plan mode for the next chunk. Stays silent when a multi-session plan is already in progress (`.claude/current_plan.md`). Aimed at beginners, for whom a giant uncommitted diff is hard to review and easy to lose. Fires once per session. Thresholds tunable via `DEV_HOOKS_BIG_CHANGE_FILES`/`DEV_HOOKS_BIG_CHANGE_LINES`; opt out with `DEV_HOOKS_BIG_CHANGE=false`. |
| `Stop` | `change-summary-reminder.sh` | On stop, if the session changed a meaningful number of files (default: ≥ 3), nudge Claude (exit 2) to give a short, plain-language summary of what changed in each file — an aid for reviewing the session's work without re-reading the raw diff, for technical and non-technical readers alike. Fires once per session. Threshold tunable via `DEV_HOOKS_CHANGE_SUMMARY_FILES`; opt out with `DEV_HOOKS_CHANGE_SUMMARY=false`. |
| `Stop` | `save-script-reminder.sh` | On stop, if Claude wrote a script this session (a `Write` of shebang-prefixed content, **wherever** it landed — scratchpad, `/tmp`, or inside a project repo; only scripts already in a library root are excluded), nudge it (exit 2) to **decide per script**: a broadly useful tool gets genericized to the saved-script standard (PEP 723 + `uv run` shebang + `# short-description:` + `chmod +x`) and added to a library root (or a subdirectory) so the `script-index` hook surfaces it next session — even one already committed to a repo can be worth promoting — while a genuinely task-specific or throwaway script is left where it is. Points at the `script-library` skill. Fires at most once per session. Library roots come from `DEV_HOOKS_SCRIPT_DIR`; opt out with `DEV_HOOKS_SAVE_SCRIPT=false`. |

## Skills

The companion skills the hooks point at:

| Skill | Use when |
|-------|----------|
| `dev-env-setup` | Auditing/setting up a repo against an opinionated dev-env standard, version-tracked via `DEV_ENV_VERSION`: mise pinning the toolchain, an hk pre-commit hook running linters/tests + gitleaks + zizmor & actionlint (GitHub Actions security + correctness checks, v18) (Rails gets the v17 ERB + security + correctness suite — herb, brakeman, bundler-audit, importmap audit, strong_migrations, database_consistency, fasterer, rubocop plugins), a CI workflow mirroring those checks, a 4-day dependency cooldown (uv `exclude-newer` enforced on Python repos; Ruby/JS package managers documented), and project docs — a `README.md` and `CLAUDE.md` recording the project's pinned key-package versions, dispatching a subagent to create them when missing. Paired with the `dev-env-reminder` hook; trimmed from Nate Berkopec's `dev-env-setup` (kept/dropped rationale in the skill; per-version migration steps in `references/upgrade-guide.md`). Ships a fleet mode: after a standard bump, `scripts/fleet_roster.sh` discovers every `DEV_ENV_VERSION`-stamped repo live and the skill backfills them, canary first, one isolated agent per repo. |
| `github-actions` | Writing, reviewing, or hardening a GitHub Actions workflow, or bumping a whole fleet's action pins. Carries the supply-chain security checklist (SHA-pin actions, read-only `GITHUB_TOKEN`, no `pull_request_target`/untrusted input in `run:`, OIDC for cloud creds, run `actionlint` + `zizmor`) in `references/security-checklist.md`, plus the fleet-wide SHA-pin/bump procedure (`pinact run -u` + `check_action_refs.sh`). Paired with the `ci-action-ref-reminder` hook; the dev-env CI templates ship pre-hardened to this standard. |
| `dependency-upgrade` | Bringing a repo's dependencies up to the latest versions across JavaScript (npm/pnpm/yarn), Ruby (bundler), Python (uv/poetry/pip), and GitHub Actions. Reads changelogs/migration guides for **major** bumps, applies the code changes, and lands each step as its own commit — **gating every commit on a green test suite** and deferring any major it can't get green to a written report (`plans/deferred-upgrades.md`). Ships a read-only `upgrade_inventory.sh` preflight, a fleet mode (one isolated agent per repo), delegates the Actions part to `github-actions`, and respects dev-env-setup's 4-day cooldown. This is the *upgrade* counterpart to `dev-env-setup` (which only pins tooling + records versions). |
| `dockerfile` | Writing/editing a Dockerfile — cache-friendly layer ordering (least→most frequently changed) and common gotchas (pinning, multi-stage, `.dockerignore`, non-root, exec-form `CMD`). Paired with the `dockerfile-reminder` hook; delegates linting to `hadolint`. |
| `popovers-tooltips` | Building/fixing popovers, tooltips, dropdowns or menus that open off-screen or get clipped — Tailwind styles but doesn't position; use a collision-aware positioner (flip + shift) + top-layer/portal. Rails/Hotwire-first: Floating UI (`@floating-ui/dom`) in a Stimulus controller with `autoUpdate` and `disconnect()` cleanup (the Turbo gotcha), plus Tippy/Flowbite/Preline and the native Popover API. Paired with the `popover-reminder` hook. |
| `tailwind` | Writing/fixing Tailwind CSS in any template (HTML, ERB/ViewComponent, JSX, Vue) — design tokens over magic numbers, taming class soup by extracting components (not `@apply`), dark mode (with WCAG-AA contrast), mobile-first responsive, and accessibility (`focus-visible`, `sr-only`, reduced motion). Framework-neutral; pairs with `popovers-tooltips`. Adapted from the MIT-licensed [mattsears/rails-cto](https://github.com/mattsears/rails-cto) `rails-cto-tailwind` skill. |
| `accessibility` | Auditing or fixing web UI against WCAG 2.2 AA / ARIA — semantic HTML over `<div>` soup, alt text, accessible names, form labels, keyboard focus order, contrast, and reduced motion, with Rails/Hotwire (Turbo focus management, `form.label`) and React (`htmlFor`, headless-library focus traps) patterns. Ships a heuristic `a11y_audit.py` (`file:line: issue`) and a full WCAG 2.2 review checklist. Paired with the `a11y-reminder` hook. |
| `env-to-fnox` | Migrating a project's plaintext `.env` to [fnox](https://fnox.jdx.dev) — references in a committed `fnox.toml`, real values in a vault (defaults to Bitwarden Secrets Manager). Paired with the `secret-plaintext-reminder` hook. Adapted from [Nate Berkopec's dotfiles](https://github.com/nateberkopec/dotfiles) with the provider switched from 1Password to Bitwarden. |
| `worktree-setup` | Provisioning a freshly-created git worktree so it's actually ready to work in. A clean checkout is missing everything git doesn't track: an untrusted `mise.toml`, absent gitignored secrets/config (Rails `config/master.key`, `.env`, …), and shebang scripts the `core.fileMode=false` checkout dropped `+x` from. Ships `setup-worktree.sh` — run it inside the new worktree to trust mise, copy gitignored files from the main checkout (everything except heavy build/dependency dirs and the worktree itself), and re-mark scripts executable. Set `worktree.baseref head` first so the worktree branches from local HEAD. Complements `using-git-worktrees` (which creates the worktree; this provisions it). |
| `script-library` | Keeping a one-off script you wrote — genericizing it to a standalone, self-contained CLI and saving it to the reusable library (`~/.local/bin` or a cloned, shareable scripts repo organised into subdirectories). The standard: a `#!/usr/bin/env -S uv run --script` shebang + PEP 723 inline deps (Python), a `# short-description:` line the `script-index` hook surfaces, a real `argparse --help`, and `chmod +x`; strip task-specific paths into flags and never bake in secrets. Library roots are a colon-separated `DEV_HOOKS_SCRIPT_DIR` (PATH-style), each scanned recursively. Ships a copy-paste `references/template.py`. Paired with the `save-script-reminder` (Stop) and `script-index` (SessionStart) hooks. |
| `compress-comments` | Reviewing the comments a session's work added and cutting them down — after finishing a feature, before commit/merge, or when the `compress-comments-reminder` hook fires. AI-authored comments skew verbose (code-echo, change narration, planning forensics, reviewer justification); the skill is delete-biased around one survival rule — *a comment survives only if it states something the code cannot show* — with docstrings compressed but never deleted and directive comments (`noqa`, `shellcheck`, `eslint-disable`, …) never touched. Judges only the session's own diff (branch diff, or remembered commits on the default branch); ships the smell taxonomy with before/after examples in `references/comment-smells.md`. |
| `repo-review` | Reviewing/auditing a **whole repository** (not a diff) — an inherited or unfamiliar codebase, a "review this repo for 1. performance 2. code smells 3. structure" sweep. The **broader** stack-agnostic umbrella over `rails-audit`: a Rails app hands the Rails-shaped axes (correctness, security, perf, schema, tests, architecture, deps) to that deeper skill but **still** runs the cross-cutting axes `rails-audit` doesn't cover. Full axis set — correctness (`/code-review`), code smells (`/simplify`), performance, architecture, app security, test health (incl. does the suite *run* from a clean checkout), dev-env (`dev-env-setup`), dependencies/CVEs (`dependency-upgrade`), CI supply-chain (`github-actions`), secrets hygiene (`env-to-fnox`), plus accessibility (`accessibility`) and docs for web repos, and opt-in genericization. Detects monorepos (offers to review each sub-project separately). Ships a read-only `detect_stack.sh` preflight and ends in a severity-ranked `plans/repo-review-YYYY-MM-DD.md`. **Report-only** — it diagnoses, fixes are a separate scoped follow-up. The principle is *delegate, don't re-derive*. |

## Install

```bash
/plugin marketplace add mickzijdel/dev-hooks
/plugin install dev-hooks@dev-hooks
```

To receive the latest skills and hooks, enable auto-updates for the plugin in the plugin management overview.

## Usage

Once installed the **hooks fire automatically** — there is nothing to invoke. They lint
after edits, verify tests/linters before Claude stops, guard dangerous commands, and nudge
on the patterns documented above. To use a companion **skill**, describe the task and Claude
reaches for the matching one, or invoke it by name:

```console
$ claude
> /dev-hooks:dev-env-setup audit this repo against the dev-env standard
> /dev-hooks:repo-review     whole-repo severity-ranked audit
```

## Notes

- `prompt-log.sh` is the only **UserPromptSubmit** hook. It appends one JSON line per prompt
  (`ts`, `cwd`, `session_id`, `len`, `prompt` truncated to the first 500 chars) to
  `~/.claude/automation-review/prompts.jsonl`, so the `thinking-tools` `weekly-automation-review`
  skill can cluster repeated requests across **all** your repos and suggest what to turn into a
  skill/hook/tool. It is silent (it never writes to stdout — a UserPromptSubmit hook's stdout
  would be injected into Claude's context — and always exits 0, so it can never block or pollute
  a prompt). **Privacy:** the log is plaintext and may capture whatever you type (including
  secrets pasted into a prompt). It is local-only under `~/.claude/`, never transmitted, and
  capped at ~2×10 MiB (it rotates to `prompts.jsonl.1` past the cap, default 10 MiB,
  `DEV_HOOKS_PROMPT_LOG_MAX_BYTES`). Disable logging entirely with `DEV_HOOKS_PROMPT_LOG=false`
  (in `.claude/settings.local.json` `"env"`); delete the `~/.claude/automation-review/` directory
  to purge history.
- `verify-work.sh` only runs inside a git repo and only when relevant code files have
  changed; it no-ops otherwise.
- `dev-env-reminder.sh` only nudges on repos it judges **yours** and only when the standard
  applies but isn't met; it's advisory and never edits anything. Ownership = origin remote
  owner listed in `DEV_HOOKS_DEVENV_OWNERS` **or** ≥80% of the last month's commits authored by
  your local `git config user.email`. Tune/override via env (set in `.claude/settings.local.json`
  `"env"`): `DEV_HOOKS_DEVENV_OWNED` (`true`/`false` — deterministic per-repo override, `false`
  silences it entirely), `DEV_HOOKS_DEVENV_OWNERS` (GitHub owners to treat as yours, e.g. your
  username or an org you own), `DEV_HOOKS_DEVENV_EMAIL` (commit-author email for the heuristic;
  defaults to your local `git config user.email`).
  Per-repo opt-out also via a `dev-env: skip` line in the project's `CLAUDE.md`.
- `docs-context.sh` scans `docs/` (falling back to `doc/`) at the project root for Markdown
  files up to two levels deep. Titles come from YAML frontmatter (`title:`) or the first `#`
  heading; an optional frontmatter `description:` field is included after an em-dash. Hidden
  paths (`.*`) are ignored. Silence it with `DEV_HOOKS_DOCS_CONTEXT=false` (in
  `.claude/settings.local.json` `"env"`).
- `memory-reminder.sh` targets Claude Code's file-based memory feature. It stays a no-op
  unless you set `DEV_HOOKS_MEMORY=1` or have already used memory somewhere (it detects any
  existing `~/.claude/projects/*/memory/` dir), so it's safe for installers who don't use
  memory. It only nudges Claude to capture learnings — it never writes memory or edits
  CLAUDE.md itself, and Claude is told to save nothing when there's nothing durable.
  "Substantial session" defaults to ≥ 6 human turns; tune with `DEV_HOOKS_MEMORY_MIN_TURNS`
  (in `.claude/settings.local.json` `"env"`).
- `script-index.sh` (SessionStart) and `save-script-reminder.sh` (Stop) are a pair that make
  a CLI-tool library self-stocking and self-advertising. Both read the library roots from
  `DEV_HOOKS_SCRIPT_DIR` — a colon-separated list like `PATH` (default `~/.local/bin`, which is
  already on `PATH`), so you can keep personal scripts **and** a cloned, shareable scripts repo,
  e.g. `~/.local/bin:~/code/team-scripts`. Each root is scanned **recursively** (hidden dirs like
  `.git` skipped, depth-capped), so a repo organised into subdirectories works; the index shows
  each script's path, since a script in a subdirectory or a non-`PATH` root is run by path or via
  `uv run <path>` rather than bare name. `script-index` reads only the **first lines** of each
  executable shebang file (for the `# short-description:`); it never runs a script. Hide
  entries that aren't your own tools — installed/third-party CLIs, app launchers — with
  `DEV_HOOKS_SCRIPT_IGNORE`, a colon-separated list of globs matched against each script's
  basename or full path (e.g. `*vocalinux*:gext:gnome-extensions-cli`).
  `save-script-reminder` detects a script Claude wrote via the **Write** tool whose content
  starts with a shebang, **wherever** it landed (only scripts already in a library root are
  excluded — in-repo scripts are listed too, so Claude can decide whether each is project-
  specific or a general tool worth promoting); a script created through a Bash heredoc isn't
  detected (the Write path is the common case).
  Disable independently with `DEV_HOOKS_SCRIPT_INDEX=false` / `DEV_HOOKS_SAVE_SCRIPT=false` (in
  `.claude/settings.local.json` `"env"`). See the `script-library` skill for the saved-script
  standard and how to share a scripts repo.
- `latest-deps-reminder.sh` is reminder-only — it never queries a package registry, just
  nudges Claude to look up current versions itself (training data goes stale). On manifest
  edits (python/js/ruby — not lockfiles) it additionally reminds Claude to keep README.md
  and CLAUDE.md key-package versions in sync, creating those docs if they don't exist. It
  fires at most once per session per ecosystem (python/js/ruby/lockfile), tracked via a
  marker under `${TMPDIR:-/tmp}/dev-hooks-latest-deps/`. Silence it with
  `DEV_HOOKS_LATEST_DEPS=false` (in `.claude/settings.local.json` `"env"`).
- `scaffold-reminder.sh` is reminder-only — it never blocks the write. It fires when the
  Write tool creates a project manifest or framework entrypoint that git doesn't already
  track (outside a git repo every file counts as new): hand-writing one of those is the
  signature of scaffolding a project from memory. Edits stay silent (the project already
  exists), as do tracked files. The nudge names the matching generator (`rails new`,
  `npm create vite@latest`, `uv init`/`django-admin startproject`, `cargo new`,
  `go mod init`, `mix new`/`mix phx.new`, `composer create-project`, `gradle init`, …)
  and tells Claude to first check the framework's current stable release — and the
  generator's current flags via `--help`/docs — rather than recalling either, unless the
  user asked for a specific version. Fires once per session, tracked via a marker under
  `${TMPDIR:-/tmp}/dev-hooks-scaffold/`. Silence it with `DEV_HOOKS_SCAFFOLD=false`
  (in `.claude/settings.local.json` `"env"`).
- `dockerfile-reminder.sh` runs [`hadolint`](https://github.com/hadolint/hadolint) on each
  `Dockerfile`/`Containerfile` Claude writes and reports the findings (or a clean pass) back
  to Claude, plus a layer-ordering nudge pointing at the `dockerfile` skill. It's report-only:
  it surfaces results every time but never blocks the write — Claude decides whether to fix.
  If `hadolint` isn't installed it can't lint, so it falls back to a once-per-session
  ordering/gotchas reminder (tracked via a marker under `${TMPDIR:-/tmp}/dev-hooks-dockerfile/`)
  and suggests installing hadolint. Silence the whole hook with `DEV_HOOKS_DOCKERFILE=false`
  (in `.claude/settings.local.json` `"env"`).
- `popover-reminder.sh` is reminder-only — it never blocks the write. It fires when Claude
  writes a frontend file (the shared extension list below, same as `inline-svg-reminder.sh`)
  carrying a popover/tooltip signal: a popover/tooltip/dropdown/popper/floating
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
  Claude writes a `*.yml`/`*.yaml` that pins a remote action (`uses: owner/repo@ref`), points
  Claude at the `github-actions` skill's supply-chain checklist (SHA-pin actions, read-only
  token, no untrusted input in `run:`), and at the bundled
  `skills/dev-env-setup/scripts/check_action_refs.sh`, which does the actual `git ls-remote`
  resolution and exits non-zero on any unresolved ref. That script classifies each ref as
  `OK` (a tag resolves, or a SHA pin's `# vX.Y.Z` comment matches the commit that tag points
  to) / `FAIL` (missing tag, or a SHA that doesn't match its comment) / `PIN` (a SHA with no
  version comment) / `SKIP` (remote unreachable — never a failure), so offline runs don't
  false-alarm; you can also run it directly over a workflow or `.github/workflows`. Fires once
  per session per file (marker under `${TMPDIR:-/tmp}/dev-hooks-ci-action-refs/`). Silence it
  with `DEV_HOOKS_CI_ACTION_REFS=false`
  (in `.claude/settings.local.json` `"env"`).
- `inline-svg-reminder.sh` is the one **enforcing** PostToolUse hook: the write still lands,
  but it feeds a correction back (exit 2) on **every** occurrence rather than once per
  session — hand-written inline SVG is a habit worth breaking, not a one-time tip. It fires
  when Claude writes a frontend file (`.js`/`.mjs`/`.cjs`/`.jsx`/`.ts`/`.tsx`/`.vue`/`.svelte`/
  `.astro`/`.html`/`.htm`/`.erb`/`.haml`/`.slim`/`.php`/`.twig`/`.heex`/`.css`/`.scss`)
  containing an `<svg>` block with real drawing content (`<path>`/`<circle>`/`<rect>`/… or
  substantial `d="M…"` path data), a partial drawing fragment, or a `data:image/svg+xml` URI.
  The feedback says, in order of preference: use the project's icon library (it greps
  `package.json`/`Gemfile` and names the one already installed — lucide, heroicons, tabler,
  font-awesome, …), else extract the markup to a dedicated `.svg` file/sprite and reference
  it; keep it inline only if the user explicitly asked. The *good* patterns never fire:
  `<svg><use href="sprite.svg#id">` references, writing actual `.svg` files (the refactor
  target), `<img src="x.svg">`, markdown/docs, test files, and data-driven chart markup
  (drawing tags with expression attributes like `<rect x={scale(d)}>` — D3/visx charts
  aren't icons). Pre-existing, user-approved inline SVG doesn't re-trigger: full-file
  Writes are deduped against the file at `HEAD`, Edits/MultiEdits against their
  `old_string`s, keyed on the `d="…"` drawing data so attribute tweaks on an approved icon
  stay silent. Silence it
  with `DEV_HOOKS_SVG_INLINE=false` (in `.claude/settings.local.json` `"env"`).
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
- `dangerous-command-guard.sh` is the only **PreToolUse** hook and the only one that can
  *block* a tool call. It reads the bash command from the hook payload (never runs or modifies
  it) and emits a `permissionDecision` of `deny` (catastrophic, irreversible commands) or `ask`
  (risky-but-legitimate — forces a human confirmation); for everything else it stays silent and
  the normal permission flow proceeds. It never emits `allow`, so it can't widen your own
  allowlist. Detection is deliberately conservative — a short list of well-known footguns, not
  "anything that writes" — and it splits the command into simple-command segments (`;`, `&`,
  `|`, newlines) so flags and targets are only judged against the command they belong to
  (`cd ~ && rm -rf build/` is not `rm -rf ~`; a commit message that *mentions* `mkfs` is not
  `mkfs`). The commit/push-on-`main`/`master` check is **opt-in** via `DEV_HOOKS_GUARD_MAIN=1`
  (the `coding-onboarding` plugin's `getting-started` skill seeds it for beginners when
  installed — solo main-branch workflows aren't prompted on every commit); when on, it checks
  the current branch with `git branch --show-current` in the call's cwd. Silence the whole
  guard with `DEV_HOOKS_BASH_GUARD=false` (in `.claude/settings.local.json` `"env"`).
- `big-change-reminder.sh` runs only in a git repo and sizes the **uncommitted** working tree
  (tracked changes from `git status --porcelain` plus untracked files enumerated via
  `git ls-files --others` — so files inside a brand-new directory are counted individually;
  added lines from `git diff HEAD --numstat` plus the line count of untracked files). It
  fires (exit 2, once per session via a transcript
  sentinel) only above the thresholds (`DEV_HOOKS_BIG_CHANGE_FILES` default 25,
  `DEV_HOOKS_BIG_CHANGE_LINES` default 800) and stays silent when `.claude/current_plan.md`
  exists — a plan already means the work is deliberate. Silence it with
  `DEV_HOOKS_BIG_CHANGE=false`.
- `change-summary-reminder.sh` counts changed files via the simpler `git status --porcelain`
  tally (an untracked directory collapses to one entry — unlike `big-change-reminder.sh`'s
  line-count-accurate expansion, that's fine here since it's only a file-count threshold), and
  it doesn't inspect diff size at all — it's about getting a **readable account** of the
  changes, not their bulk. It doesn't check whether a summary was already given earlier in the
  session; the once-per-session sentinel is enough, and the reminder text itself tells Claude
  it's fine to skip repeating one.
- Nearly all the hooks build on `hooks/scripts/lib/reminder-common.sh`, the shared library
  that owns payload extraction, opt-out handling, and advisory/blocking emit. Its content
  helpers understand Write `content`, Edit `new_string`/`old_string`, and MultiEdit `edits[]`
  alike, so the content-reading hooks (`secret-plaintext-reminder.sh`, `inline-svg-reminder.sh`,
  `a11y-reminder.sh`, …) all see the written text the same way.
- Hooks require `jq` (used to parse hook input) and, for `a11y-reminder.sh`,
  `debug-leftover-reminder.sh`, `error-swallow-reminder.sh`, `inline-svg-reminder.sh`,
  `memory-reminder.sh`, `missing-test-reminder.sh`, `review-reminder.sh`,
  `secret-plaintext-reminder.sh`, `sql-injection-reminder.sh`, `todo-leftover-reminder.sh`,
  and `verify-work.sh`, `python3`.
- The `dev-env-setup` skill applies a [mise](https://mise.jdx.dev)/[hk](https://hk.jdx.dev)
  standard, so the repos it sets up depend on `mise`, `hk`, `pkl`, `gitleaks`, `zizmor`,
  `actionlint` (and `shellcheck`/`shfmt` for shell repos) — all provisioned via the generated
  `mise.toml`. The
  `dev-env-reminder` hook itself only needs `git`, `jq`, and `bash`.

## License

[MIT](../../LICENSE)
