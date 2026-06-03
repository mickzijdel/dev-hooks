# dev-hooks

A Claude Code plugin bundling four polyglot, project-agnostic dev-workflow hooks. Each
script detects the project's own toolchain (Ruby/Rails, JavaScript/TypeScript, Python) —
there is nothing to configure.

## What's included

| Event | Script | Purpose |
|-------|--------|---------|
| `PostToolUse` (`Write`\|`Edit`) | `lint-on-edit.sh` | Auto-fix/format the file Claude just wrote using the linter **this** project configures (RuboCop/Standard, erb_lint, Biome/Prettier/ESLint, Ruff/Black). Safe fixes only, never blocks. |
| `Stop` | `verify-work.sh` | On stop, detect changed code files and run the project's linters/tests (RuboCop, Minitest/RSpec, Ruff/pytest, ESLint/JS tests). Feeds failures back to Claude (exit 2) so it fixes them before finishing. |
| `SessionStart` | `detect-stack-skills.sh` | Detect the project's stack and remind Claude to consult applicable skills/conventions before writing code. |
| `Stop` | `plan-reminder.sh` | If `.claude/current_plan.md` exists and is stale, remind Claude to update the multi-session plan before ending. |

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
- Hooks require `jq` (used to parse hook input) and, for `verify-work.sh`, `python3`.
