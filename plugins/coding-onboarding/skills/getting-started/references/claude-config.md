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
  or home directory (`rm -rf /`), a fork bomb, formatting/overwriting a drive, making the whole
  system world-writable. These are the ones you should never be able to approve by reflex, so
  the guard doesn't even offer the choice.
- **Asks before committing/pushing straight to `main`** — a workflow-habit nudge while you're
  learning the branch-and-PR way of working. This one is opt-in, via `DEV_HOOKS_GUARD_MAIN=1`
  in the settings template above.
- **Stays out of the way** for everything else.

Everyday risky-but-legitimate commands — `rm -rf some/folder`, throwing away uncommitted work
(`git reset --hard`), force-pushing, `sudo` — are *not* the guard's job. Layer 1's allowlist
already leaves all of those asking (only safe, read-only commands are pre-approved), so you
still get a prompt; and Claude Code's own auto mode flags them too. The guard deliberately
doesn't pile a second confirmation on top of a built-in one.

Every block comes with a plain-language reason so you learn *why* it's dangerous.

Together: the config makes good behaviour the default and leaves anything that changes something
asking, and the guard is the hard backstop for the catastrophic few. Both are adjustable — the
allowlist and CLAUDE.md are yours to edit, and the guard's block can be softened to a confirm
(`DEV_HOOKS_GUARD_DENY=ask`) or turned off entirely (`DEV_HOOKS_BASH_GUARD=false`) if you ever
need it gone.

## A note on trust

The guard is a seatbelt, not autopilot. Read what the agent proposes, especially when a prompt
asks you to confirm something — it exists precisely because that command changes something and
deserves a human look. As you get comfortable, you'll know which to wave through and which to
question.

## As you get comfortable: auto mode

Claude Code has an **auto mode** that stops asking permission for most commands and instead lets
a built-in safety check catch the genuinely dangerous ones on its own — the same kinds of
protection that, in the normal mode you're starting in, show up as permission prompts and the
guard above. It's newer and still being refined (Anthropic calls it a research preview), so
treat it as something to grow into, not a starting point.

The reason to wait: while you're learning, the prompts *are* the lesson. Each one is a moment to
read what the agent wants to do and ask yourself "do I understand why this is safe?" Turn that
off too early and you skip the part that builds your judgement. Once reading a command and
deciding whether to allow it is second nature, auto mode is a reasonable way to cut the noise.
