# Troubleshooting

Common stumbles during setup, with the fix. Check here before improvising.

## `mise: command not found` after installing it

mise installs to `~/.local/bin` and adds an activation line to your shell config, but the
current terminal hasn't picked it up. **Open a new terminal**, or `source ~/.bashrc` /
`source ~/.zshrc`. Confirm with `mise --version`. If still missing, make sure the activation
line (`eval "$(~/.local/bin/mise activate bash)"` or the zsh equivalent) is in your shell rc.

## A tool installed by mise isn't found (`node`/`pnpm`/`uv`…)

Same cause: mise must be **activated** in the shell for its tools to land on `PATH`. New
terminal, or `source` your rc. Check what mise sees with `mise ls`.

## `brew: command not found` (macOS)

Homebrew isn't installed — it's the package manager that gets you GUI apps like VS Code. Install
it from <https://brew.sh> (confirm the command with the user first), then re-run the VS Code
step.

## `code: command not found` (macOS, VS Code already installed)

The `code` CLI isn't on `PATH` yet. Open VS Code → Command Palette (`Cmd+Shift+P`) → **"Shell
Command: Install 'code' command in PATH"**. Then reopen the terminal.

## Native Windows — nothing works / `os=unknown`

This skill is bash-only and targets macOS, Linux, and **WSL2**. On Windows:

1. Open **PowerShell as Administrator** and run `wsl --install`.
2. Reboot, finish the Ubuntu first-run (set a username/password).
3. Open the **Ubuntu/WSL** terminal and re-run the skill *there*.

Docker Desktop and VS Code install on the Windows side and connect to WSL automatically.

## `gh auth login` loops or fails in the browser

- Make sure you finished creating the GitHub account first (verify the email).
- Choose **GitHub.com → HTTPS → Login with a web browser** and approve `gh` as the git
  credential helper.
- In a headless/remote shell with no browser, pick the **"Paste an authentication token"** path
  and create a token at <https://github.com/settings/tokens> with `repo` + `read:org` scope.
- Verify with `gh auth status`.

## `git push` asks for a username/password every time

`gh` wasn't set as the credential helper. Run `gh auth setup-git` (or re-run `gh auth login` and
approve the credential-helper step).

## Docker: `permission denied` on the socket (Linux)

Your user isn't in the `docker` group yet. `sudo usermod -aG docker $USER`, then **log out and
back in** (or `newgrp docker`). Test with `docker run hello-world`.

## Playwright: browser fails to launch (Linux/WSL)

Missing system libraries. Re-run with system deps (needs `sudo`, so confirm):
`uvx playwright install --with-deps chromium`.

## The dangerous-command guard is blocking something I actually want

If a command is genuinely safe and you want it through, run it yourself in a terminal (outside
the agent), or temporarily set `DEV_HOOKS_BASH_GUARD=false` in your Claude settings `"env"`.
If it's only the commit/push-on-`main` confirmation you've outgrown (you now work on `main`
deliberately), remove just `DEV_HOOKS_GUARD_MAIN` from the settings `"env"` and keep the rest
of the guard. For the *big-change* nudge, set `DEV_HOOKS_BIG_CHANGE=false`. Turn them back on
afterwards — they're cheap insurance.

## I want to undo something Claude did

If it was committed, nothing is lost — see "Undoing mistakes" in
[`git-basics.md`](git-basics.md). If it isn't committed yet and you want to keep it, commit it
to a branch first, *then* experiment.
