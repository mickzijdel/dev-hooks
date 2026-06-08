# dev-hooks

A Claude Code plugin bundling six polyglot, project-agnostic dev-workflow hooks plus a
set of thinking-tool skills. Each hook script detects the project's own toolchain
(Ruby/Rails, JavaScript/TypeScript, Python) — there is nothing to configure.

## What's included

| Event | Script | Purpose |
|-------|--------|---------|
| `PostToolUse` (`Write`\|`Edit`) | `lint-on-edit.sh` | Auto-fix/format the file Claude just wrote using the linter **this** project configures (RuboCop/Standard, erb_lint, Biome/Prettier/ESLint, Ruff/Black). Safe fixes only, never blocks. |
| `Stop` | `verify-work.sh` | On stop, detect changed code files and run the project's linters/tests (RuboCop, Minitest/RSpec, Ruff/pytest, ESLint/JS tests). Feeds failures back to Claude (exit 2) so it fixes them before finishing. |
| `SessionStart` | `detect-stack-skills.sh` | Detect the project's stack and remind Claude to consult applicable skills/conventions before writing code. |
| `Stop` | `plan-reminder.sh` | If `.claude/current_plan.md` exists and is stale, remind Claude to update the multi-session plan before ending. |
| `Stop` | `review-reminder.sh` | On stop, if code files changed but no code review ran this session (scans the transcript for `/code-review`, the code-reviewer agent, or `requesting-code-review`), remind Claude (exit 2) to run a review and keep iterating until it comes back clean. Fires at most once per session. |
| `Stop` | `memory-reminder.sh` | On stop of a substantial session (≥ 6 human turns), remind Claude (exit 2) to capture durable, non-obvious learnings into its file-based memory — memory dir only, never CLAUDE.md, with an explicit "nothing worth saving" escape hatch. Fires at most once per session. Opt-in via `DEV_HOOKS_MEMORY=1`, or auto-enabled once you use Claude's memory feature anywhere. |

## Skills

On-demand "thinking tools" and writing/content helpers you invoke as slash commands (or that I
reach for when the trigger fits). The first group are critique/decision/automation workflows
distilled from the `#ai-productivity-digest` tips; the second group are writing/content skills
adapted from [Nate Berkopec's dotfiles](https://github.com/nateberkopec/dotfiles).

| Skill | Use when |
|-------|----------|
| `but-for-real` | About to claim something is done/fixed/working — forces re-reading the real code, running it, and separating verified from assumed. |
| `premortem` | Before committing to a non-trivial plan — imagines it already failed and works backward to failure modes, hidden assumptions, and a revised plan. |
| `board` | You want hard, independent critique — convenes a panel of real parallel advisor subagents, then a chairman synthesizes. |
| `self-rate` | Before returning uncertain work — scores it on a calibrated scale, then tightens overclaims to match. |
| `weekly-automation-review` | Weekly cadence — reviews recent activity and recommends 1–2 repetitive tasks to automate; runs as a scheduled Monday remote agent. |
| `github-readme` | Creating/revising a GitHub README — section order, onboarding flow, runnable quickstart, plus an audit script and advanced GFM features. |
| `humanizer` | Removing tells of AI-generated writing — em-dash overuse, rule-of-three, promotional tone, etc. (based on Wikipedia's "Signs of AI writing"). |
| `readability` | Making web copy scannable — inverted pyramid, plain language, plus Flesch-Kincaid/vocabulary audit scripts. |

> `github-readme`, `humanizer`, and `readability` are adapted **verbatim** from
> [Nate Berkopec's dotfiles](https://github.com/nateberkopec/dotfiles) (credit to Nate; each
> `SKILL.md` links back to its source). `humanizer` is additionally based on
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
- `memory-reminder.sh` targets Claude Code's file-based memory feature. It stays a no-op
  unless you set `DEV_HOOKS_MEMORY=1` or have already used memory somewhere (it detects any
  existing `~/.claude/projects/*/memory/` dir), so it's safe for installers who don't use
  memory. It only nudges Claude to capture learnings — it never writes memory or edits
  CLAUDE.md itself, and Claude is told to save nothing when there's nothing durable.
- Hooks require `jq` (used to parse hook input) and, for `verify-work.sh` and
  `memory-reminder.sh`, `python3`.
- The `github-readme` and `readability` skills bundle optional `ruby` audit scripts
  (`scripts/*.rb`); they only run when you invoke the skill and ask for the audit.
