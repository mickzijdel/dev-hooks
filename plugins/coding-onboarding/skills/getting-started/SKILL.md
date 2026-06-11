---
name: getting-started
version: 1.0.0
description: |
  Use when someone new to coding (or to AI-assisted coding) needs their machine set up — they
  say "set me up", "onboard me", "I just installed Claude Code", ask how to start coding with
  Claude, or want an existing setup checked or brought up to date (toolchain, editor, Docker,
  GitHub, Claude config). Idempotent and safe to re-run. macOS, Linux, and WSL2.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - Task
  - AskUserQuestion
  - WebFetch
---

# getting-started

Get someone from a fresh machine to "I can build and ship something with Claude Code." Written
for people **new to coding** — so the bar is not just "tools installed" but "they understand
what just happened and won't get their agent into trouble."

Two rules that shape everything below:

- **Idempotent + upgrade-aware.** Re-running is always safe. Every step checks what's already
  there (via the audit script) and either installs what's missing or upgrades what's behind —
  never a blind re-install. mise does the heavy lifting: `mise install` reproduces, `mise
  upgrade` brings tools current.
- **Detect, then confirm.** Install CLI tools as you go, but **stop and ask the user before**
  anything that needs `sudo`, installs a GUI app (VS Code, Docker), or changes their global
  Claude config. Explain what each thing is *for* in plain language as you go — link the
  reference docs rather than dumping walls of text.

## Platform

macOS, Linux, and **WSL2** (all bash). If the audit reports `os=unknown` or the user is on
**native Windows**, the first task is WSL2: have them run `wsl --install` in an admin
PowerShell, reboot, then re-run this skill **inside the Ubuntu/WSL shell**. Docker Desktop and
VS Code install on the Windows side and integrate with WSL automatically; everything else lives
in WSL. Don't attempt a PowerShell-native install.

## Workflow

### 1. Audit

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/getting-started/scripts/onboard_check.sh"
```

(`$CLAUDE_PLUGIN_ROOT` is set when run as a plugin; otherwise use the skill dir.) It prints
`os`, `arch`, `pkg_mgr`, an `installed`/`missing` line (+ version) per tool, `gh_auth`,
`git_identity`, and `playwright_browsers`. **Read it first** and only act on what's missing or
out of date. Show the user a short "here's what you have / what I'll add" summary before
touching anything.

### 2. mise — the toolchain backbone

Everything in the CLI column flows through [mise](https://mise.jdx.dev), so upgrades are one
command forever after. If `mise=missing`, install it (confirm first — it modifies the shell
profile):

```bash
curl https://mise.run | sh        # then add the shown `mise activate` line to the shell rc
```

Then pin the global tools (idempotent — re-running just re-resolves):

```bash
mise use -g node@lts pnpm python uv jq ripgrep gitleaks github-cli
```

`github-cli` provides `gh`. With mise already present and tools installed, **upgrade the
behind ones** instead:

```bash
mise outdated        # show what's behind
mise upgrade         # bring everything current (respects the lockfile / release-age cooldown)
```

> Tell the user to open a **new terminal** (or `source` their rc) after the first mise install
> so the tools land on `PATH`. Re-run the audit to confirm.

### 3. GitHub — account, login, identity

`gh` is the gateway. In order:

1. **Account.** If they don't have one, open <https://github.com/signup> and walk them through
   it (verify email, pick a username they're happy to keep). Wait for them to finish.
2. **Login.** `gh auth login` — choose GitHub.com → HTTPS → "Login with a web browser", and
   approve `gh` as the **git credential helper** when prompted (so `git push` just works). Skip
   if `gh_auth=yes`.
3. **Identity.** If `git_identity=no`, set the name/email every commit is stamped with:
   ```bash
   git config --global user.name "Their Name"
   git config --global user.email "the-email-on-their-github@example.com"
   ```
   Use the email tied to their GitHub account so commits link to their profile.

If they've never used Git, this is the moment to point them at
[`references/git-basics.md`](references/git-basics.md) and give them the 2-minute version (see
that file) before moving on.

### 4. VS Code + the Claude Code extension  *(confirm — GUI install)*

If `code=missing`, install VS Code (confirm first):

- **macOS:** `brew install --cask visual-studio-code` (install Homebrew first if `pkg_mgr` is
  not `brew` — `https://brew.sh`, confirm).
- **Linux/WSL:** Microsoft's apt/dnf repo (the
  [official steps](https://code.visualstudio.com/docs/setup/linux)); needs `sudo`, so confirm.
  On WSL, VS Code is usually installed on Windows and reached with `code .` from WSL.

Then add the extension so Claude runs *inside* the editor (plan review, inline edits):

```bash
code --install-extension anthropic.claude-code     # re-run with --force to update
```

Already installed? Offer `code --install-extension anthropic.claude-code --force` to update it.

### 5. Docker  *(confirm — heavy / licensed)*

If `docker=missing`, confirm before installing — it's large and Docker Desktop has licensing
terms for big companies:

- **macOS / Windows(WSL):** Docker Desktop (download, or `brew install --cask docker` on macOS).
- **Linux:** Docker Engine via the official convenience script (`curl -fsSL
  https://get.docker.com | sh`) — this needs `sudo` **and** pipes a remote script to a shell,
  so explain it and get explicit approval, then add them to the `docker` group.

Verify with `docker run hello-world`. Pair this with the bundled [[dockerfile]] skill when they
write their first Dockerfile.

### 6. Playwright browsers

The agent uses Playwright to open a real browser and screenshot the app (drives the [[verify]]
and `run` workflows, and is **required by vischeck**). With `uv` present:

```bash
uvx playwright install chromium       # idempotent; re-run after Playwright upgrades
```

On Linux/WSL add `--with-deps` if a launch complains about missing system libraries (needs
`sudo` — confirm). For JS projects that bundle Playwright, the project-local path is `npx
playwright install`.

### 7. Plugins

Install inside an active Claude Code session (each is idempotent):

```text
/plugin marketplace add mickzijdel/dev-hooks
/plugin install dev-hooks@dev-hooks
/plugin install thinking-tools@dev-hooks
/plugin install writing@dev-hooks
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
/plugin install github:mickzijdel/vischeck
```

The first command registers the marketplace this very skill ships from; the three installs
are its sibling plugins:

- **dev-hooks** — the safety net: lint-on-edit, verify-before-stop, secret/debug/missing-test
  reminders, and the beginner guardrails (the dangerous-command guard + big-change reminder —
  the guard's commit-to-main check is what `DEV_HOOKS_GUARD_MAIN` in step 8 switches on).
- **thinking-tools** — pushback on demand: adversarial critique (board), premortems, and
  "did you actually run it?" checks (but-for-real, self-rate).
- **writing** — README structure, readability, and de-AI-ing prose (github-readme,
  readability, humanizer).
- **Superpowers** — an agentic skills/methodology framework.
- **vischeck** — visual UI verification (authenticated screenshots + a review rubric); it needs
  `uv` and the chromium browser from step 6, both already set up.

### 8. Seed beginner-safe Claude config  *(confirm — writes ~/.claude)*

Two pieces, both written to the user's `~/.claude/` after showing them the diff:

1. **Permissions allowlist** — so they aren't drowned in prompts for harmless commands while
   *mutating* commands still ask. Start from
   [`references/templates/settings.allowlist.json`](references/templates/settings.allowlist.json)
   and merge it into `~/.claude/settings.json` using the **[[update-config]]** skill (don't
   hand-edit settings.json — that skill owns it). The template also sets
   `DEV_HOOKS_GUARD_MAIN=1`, switching on the dangerous-command guard's **opt-in** "confirm
   before committing/pushing straight to `main`" check — right for someone building the
   branch-and-PR habit. After they've worked for a bit, the
   **[[fewer-permission-prompts]]** skill tailors the list to their actual usage.
2. **Global CLAUDE.md defaults** — beginner-safe working rules (plan big tasks first, keep
   changes small and committed, never commit secrets, confirm before destructive ops). Copy
   [`references/templates/CLAUDE.defaults.md`](references/templates/CLAUDE.defaults.md) to
   `~/.claude/CLAUDE.md`, or merge into an existing one.

See [`references/claude-config.md`](references/claude-config.md) for how these two work together
with the dangerous-command guard (config sets expectations; the hook enforces at runtime).

### 9. Orient — Git and shipping

Round it off with the two things a beginner needs next, lightly:

- **Git** — if they're new to it, give the short tour from
  [`references/git-basics.md`](references/git-basics.md): the everyday loop, branches & pull
  requests, and how to undo mistakes safely. Don't lecture — point them there and answer
  questions.
- **Building and shipping something** — when they're ready to make their first project, hand off
  to the [[starting-a-project]] skill: a "what are you building?" decision tree that picks a stack
  (Astro, React + Vite, Rails/Django, FastAPI, Python + uv, Expo, Streamlit) and then walks them
  through putting it online (GitHub Pages → full-app hosts). Don't duplicate that here — point
  them at it.

[`references/tools.md`](references/tools.md) explains, in plain language, what every tool is and
why it's there — link it for the curious.

### 10. Verify + report

Re-run the audit and report real results, not assumptions:

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/getting-started/scripts/onboard_check.sh"
```

Confirm each line that was `missing` is now `installed`, `gh_auth=yes`, `git_identity=yes`, and
`playwright_browsers=installed`. List anything still outstanding (e.g. a GUI install the user
declined, or a `sudo` step they need to run themselves) and what's left for them to do.

## Notes

- **Never auto-run the destructive/confirm steps.** sudo, Docker, VS Code, the mise profile
  edit, `~/.claude` writes, and `--with-deps` all wait for explicit user approval.
- This skill bootstraps a *machine*. To bring a *repo* up to the full mise/hk/CI/gitleaks
  standard, that's the separate [[dev-env-setup]] skill — mention it once they have a project,
  don't run it here.
- `troubleshooting.md` collects the common stumbles (PATH after mise install, no Homebrew, WSL
  not enabled, `gh auth` loops, `code` CLI missing on macOS) — check it before improvising.
