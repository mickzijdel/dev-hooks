---
name: script-library
description: Use when a one-off script you wrote is worth keeping — to genericize it and save it to the reusable CLI library (~/.local/bin). Triggers when the save-script-reminder hook fires, or the user says "save this script", "make this a CLI tool", or "add it to my scripts".
---

# Script library

A standing collection of small CLI tools in `~/.local/bin` (already on `PATH`). The
`script-index` SessionStart hook lists them — name + `# short-description:` — at the start of
every session, so a saved script becomes reusable knowledge, like a lightweight skill. The
`save-script-reminder` Stop hook nudges you here when you wrote a one-off script this session.

Use this skill to turn a throwaway script into a first-class library tool.

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

```bash
cp the-script.py ~/.local/bin/fetch-pr-diff   # pick a short, command-like name (no .py needed)
chmod +x ~/.local/bin/fetch-pr-diff           # required — it's invoked by bare name
fetch-pr-diff --help                          # verify it runs standalone and help reads well
```

Run it once to confirm it works end-to-end (per "Always Works" — don't assume). It's on `PATH`,
so the next session's script-index hook will list it by name and description automatically.

## Adding a description to an existing tool

When the index reports a script with **no `# short-description:`**, and you're using it: run
`<name> --help` to learn what it does, then tell the user — and offer to add a
`# short-description:` line near the top so it's described from then on.
