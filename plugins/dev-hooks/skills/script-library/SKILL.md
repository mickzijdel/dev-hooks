---
name: script-library
description: Use when a one-off script you wrote is worth keeping — to genericize it and save it to the reusable CLI library (~/.local/bin or a shared scripts repo). Triggers when the save-script-reminder hook fires, or the user says "save this script", "make this a CLI tool", or "add it to my scripts".
---

# Script library

A standing collection of small CLI tools. The `script-index` SessionStart hook lists them —
path + `# short-description:` — at the start of every session, so a saved script becomes
reusable knowledge, like a lightweight skill. The `save-script-reminder` Stop hook nudges you
here when you wrote a one-off script this session.

Use this skill to turn a throwaway script into a first-class library tool.

## Where the library lives

The library is one or more **roots** in `DEV_HOOKS_SCRIPT_DIR` — a colon-separated list like
`PATH` (default `~/.local/bin`). Each root is scanned **recursively**, so a root can be a git
repo organised into subdirectories:

```
DEV_HOOKS_SCRIPT_DIR=~/.local/bin:~/code/team-scripts   # (in .claude/settings.local.json "env")

~/.local/bin/                 # personal, already on PATH
  dfv
~/code/team-scripts/          # a git repo — clone it, others can use it too
  git/fetch-pr-diff
  images/resize
```

- **`~/.local/bin`** is on `PATH`, so its top-level scripts run by **bare name** (`dfv`).
- A **repo root or any subdirectory** usually isn't on `PATH`, so run those by their **full
  path** (`~/code/team-scripts/git/fetch-pr-diff`) or via `uv run <path>`. The index shows each
  script's path for exactly this reason.

**To share:** put a scripts repo on a host like GitHub; teammates clone it and add its path to
their `DEV_HOOKS_SCRIPT_DIR`. A saved script committed to that repo is then available to everyone
who's cloned it.

## When to save (and when not to)

Save a script when it's **reusable beyond the current task** — you'd plausibly run it again in
another session or project. Don't save genuinely single-use throwaways, or logic that belongs in
the project's own repo (commit it there instead). If nothing qualifies, say so and move on — do
not manufacture a tool to satisfy the reminder.

## The standard for a saved script

A copy-paste starter lives at [references/template.py](references/template.py). Every saved
**Python** script keeps these four elements:

1. **Shebang** `#!/usr/bin/env -S uv run --script` — runs standalone once `uv` is installed, no
   virtualenv or `pip install`.
2. **PEP 723 block** — declare deps inline so the script is self-contained:
   ```python
   # /// script
   # requires-python = ">=3.12"
   # dependencies = ["requests"]
   # ///
   ```
   List third-party libs in `dependencies`; `uv` resolves them at run time. Use `[]` for a
   stdlib-only script.
3. **`# short-description:` line** near the top — one line, what it does and when to reach for
   it. The script-index hook surfaces exactly this:
   ```python
   # short-description: Fetch a PR's diff by number and print it to stdout.
   ```
4. **`argparse` with real `--help`** — the index points future sessions to `<script> --help` for
   detail beyond the one-liner, so make `--help` explain usage and the arguments.

A **shell** script follows the same rules minus PEP 723: `#!/usr/bin/env bash`, a
`# short-description:` line, and a usage message printed for `-h`/`--help`.

## Genericize before saving

A one-off is usually wired to the task that spawned it. Before saving:

- Replace hard-coded paths, IDs, and values with **arguments / flags** (sensible defaults are
  fine). The script should work outside the directory it was born in.
- Remove any **secrets** — read them from the environment or a flag, never bake them in.
- Make output predictable (a clear exit code; errors to stderr).
- Confirm `--help` reads well to someone who's never seen the script.

## Save it

Pick a destination root (and subdirectory, if a repo uses them), give it a short
command-like name, and make it executable:

```bash
# personal, on PATH — runs by bare name afterwards:
cp the-script.py ~/.local/bin/fetch-pr-diff
chmod +x ~/.local/bin/fetch-pr-diff
fetch-pr-diff --help

# OR into a shared scripts repo subdirectory — run by path, and commit it:
cp the-script.py ~/code/team-scripts/git/fetch-pr-diff
chmod +x ~/code/team-scripts/git/fetch-pr-diff
~/code/team-scripts/git/fetch-pr-diff --help
( cd ~/code/team-scripts && git add git/fetch-pr-diff && git commit -m "Add fetch-pr-diff" )
```

Run it once to confirm it works end-to-end (per "Always Works" — don't assume). The next
session's script-index hook lists it by path and description automatically. If you saved it to a
shared repo, commit (and push) so teammates get it.

## Adding a description to an existing tool

When the index reports a script with **no `# short-description:`**, and you're using it: run
`<path> --help` to learn what it does, then tell the user — and offer to add a
`# short-description:` line near the top so it's described from then on.
