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
It allows safe inspection commands (listing files, reading Git state, viewing files) and leaves
everything that writes, deletes, installs, or pushes still asking.

**Don't hand-edit `settings.json`.** Use the **update-config** skill — it owns that file and
merges changes correctly. Later, after you've actually been working, the
**fewer-permission-prompts** skill looks at what you really run and suggests safe additions
tailored to you.

### Global defaults (`~/.claude/CLAUDE.md`)

`CLAUDE.md` is a standing instruction file the agent reads every session. A global one in
`~/.claude/` applies everywhere. The starter
[`templates/CLAUDE.defaults.md`](templates/CLAUDE.defaults.md) encodes beginner-safe habits:
plan big tasks before diving in, keep changes small and committed, work on a branch (not
`main`), never commit secrets, and confirm before anything destructive.

These are *defaults* — a specific project can override them with its own `CLAUDE.md`.

## Layer 2 — the dangerous-command guard (enforces)

Config is guidance the agent usually follows. The **dangerous-command guard** (a dev-hooks
PreToolUse hook) is enforcement that runs the instant a command is about to execute, no matter
what the agent intended:

- **Blocks outright** the handful of truly catastrophic, irreversible commands — wiping the disk
  or home directory, a fork bomb, formatting/overwriting a drive, making the whole system
  world-writable.
- **Pauses for your confirmation** on risky-but-legitimate ones — `rm -rf`, throwing away
  uncommitted work (`git reset --hard`, `git clean -f`), force-pushing, committing/pushing
  straight to `main`, piping a downloaded script into a shell, or `sudo`.
- **Stays out of the way** for everything else.

Every block/confirmation comes with a plain-language reason so you learn *why* it's risky.

Together: the config makes good behaviour the default, and the guard catches the dangerous
exception before it happens. Both are adjustable — the allowlist and CLAUDE.md are yours to
edit, and the guard turns off with `DEV_HOOKS_BASH_GUARD=false` if you ever need it gone.

## A note on trust

The guard is a seatbelt, not autopilot. Read what the agent proposes, especially when it asks
you to confirm something — the prompt exists precisely because that command deserves a human
look. As you get comfortable, you'll know which to wave through and which to question.
