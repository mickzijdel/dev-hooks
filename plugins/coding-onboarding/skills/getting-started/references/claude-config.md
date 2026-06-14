# Keeping the agent on the rails

Two layers work together so an AI agent helps without causing damage — one sets expectations,
the other enforces at the moment of action.

## Layer 1 — config (sets expectations)

### Permissions allowlist (`~/.claude/settings.json`)

Claude asks permission before running commands. Out of the box that means a prompt for *every*
command, including harmless ones like `ls` or `git status` — exhausting, and it trains you to
click "allow" without reading. The fix is an **allowlist**: pre-approve a set of safe,
read-only commands so prompts only appear for the commands that actually change something.

The starter list is [`templates/settings.allowlist.json`](templates/settings.allowlist.json).
It allows safe inspection commands (listing files, reading Git state, viewing files, any
`--version`/`--help`) and leaves everything that writes, deletes, installs, or pushes still
asking. It also has a small **deny** list that blocks reading secret files outright
(`.env`, `.env.*`, `secrets/`), so those never end up in the agent's context, and an **env**
entry (`DEV_HOOKS_GUARD_MAIN=1`) that switches on the guard's opt-in "confirm before
committing/pushing straight to `main`" check — right while you're building the branch-and-PR
habit. It's stack-agnostic on purpose — tailor it to what you actually run with the
**fewer-permission-prompts** skill once you've been working for a bit.

**Don't hand-edit `settings.json`.** Use the **update-config** skill — it owns that file and
merges changes correctly. Later, after you've actually been working, the
**fewer-permission-prompts** skill looks at what you really run and suggests safe additions
tailored to you.

### Global defaults (`~/.claude/CLAUDE.md`)

`CLAUDE.md` is a standing instruction file the agent reads every session. A global one in
`~/.claude/` applies everywhere. The starter
[`templates/CLAUDE.defaults.md`](templates/CLAUDE.defaults.md) encodes safe working habits that
serve everyone: be thorough rather than fast, **verify before claiming something works**
("Always Works"), plan big tasks before diving in, keep changes small and committed on a branch
(not `main`), never commit secrets, and confirm before anything destructive. Its final
`## How to explain things to me` section is the one part `getting-started` tailors to the user's
stated experience level (see [`explanation-levels.md`](explanation-levels.md)) — from
plain-words hand-holding to terse peer-level — with a date stamp that prompts a roughly monthly
comfort check-in.

These are *defaults* — a specific project can override them with its own `CLAUDE.md`.

## Layer 2 — the dangerous-command guard (enforces)

Config is guidance the agent usually follows. The **dangerous-command guard** (a dev-hooks
PreToolUse hook) is enforcement that runs the instant a command is about to execute, no matter
what the agent intended:

- **Blocks outright** the handful of truly catastrophic, irreversible commands — wiping the disk
  or home directory, a fork bomb, formatting/overwriting a drive, making the whole system
  world-writable.
- **Pauses for your confirmation** on risky-but-legitimate ones — `rm -rf`, throwing away
  uncommitted work (`git reset --hard`, `git clean -f`), force-pushing, piping a downloaded
  script into a shell, or `sudo`. With the seeded settings it also asks before
  committing/pushing straight to `main` (that check is opt-in, via `DEV_HOOKS_GUARD_MAIN=1`
  in the settings template above).
- **Stays out of the way** for everything else.

Every block/confirmation comes with a plain-language reason so you learn *why* it's risky.

Together: the config makes good behaviour the default, and the guard catches the dangerous
exception before it happens. Both are adjustable — the allowlist and CLAUDE.md are yours to
edit, and the guard turns off with `DEV_HOOKS_BASH_GUARD=false` if you ever need it gone.

## A note on trust

The guard is a seatbelt, not autopilot. Read what the agent proposes, especially when it asks
you to confirm something — the prompt exists precisely because that command deserves a human
look. As you get comfortable, you'll know which to wave through and which to question.
