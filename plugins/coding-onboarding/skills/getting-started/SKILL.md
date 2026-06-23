---
name: getting-started
version: 1.2.1
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

Get someone from a fresh machine to "I can build and ship something with Claude Code." It meets
people **wherever they are** — from someone who's never opened a terminal to an experienced
developer who's just new to AI-assisted coding — by **asking their experience level once**
(Step 2) and calibrating from there. The bar is not just "tools installed" but "they understand
what just happened, at the depth that's right for them, and won't get their agent into trouble."

Three rules that shape everything below:

- **Idempotent + upgrade-aware.** Re-running is always safe. Every step checks what's already
  there (via the audit script) and either installs what's missing or upgrades what's behind —
  never a blind re-install. mise does the heavy lifting: `mise install` reproduces, `mise
  upgrade` brings tools current.
- **Detect, then confirm.** Install CLI tools as you go, but **stop and ask the user before**
  anything that needs `sudo`, installs a GUI app (VS Code, Docker), or changes their global
  Claude config. Explain what each thing is *for* in plain language as you go — link the
  reference docs rather than dumping walls of text.
- **Teach as you go, at the right level.** Until Step 2 establishes the user's experience level,
  default to plain words and assume little prior knowledge; after it, match the explanation and
  technical depth to the rung they chose (the per-rung guidance lives in
  [`references/explanation-levels.md`](references/explanation-levels.md)). For the lower rungs:
  before each install step, say in 2–3 plain sentences what the tool is, *why this one* over the
  alternatives (why mise instead of installing ten tools separately; why uv instead of pip), and
  what would break without it; never use a term like "package manager", "CLI", "repo", or
  "environment variable" without a one-line everyday comparison the first time — the shared
  analogies live in [`references/plain-words.md`](references/plain-words.md). For an experienced
  user (top rung), skip the tutorials and keep it terse. Either way, after each major step offer a
  one-liner: "curious how this works? → [`references/tools.md`](references/tools.md)", and keep
  your own messages short — the depth lives in the references.

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

Someone who arrived via the repo's one-line bootstrap (`install.sh` — the `curl … | bash`
command in the root README) already has Claude Code, is signed in, and has this plugin
installed; the audit will show `claude=installed`. Acknowledge that ("the installer already
handled Claude Code — nice") and fast-forward to what's still missing instead of re-explaining
those steps.

**If the audit shows everything already `installed`** (a returning user, or someone whose
machine was set up elsewhere), don't end the turn with "you're all set!" — there's nothing to
install, but the user still came here to *do* something. There's nothing to install, but still
do **step 2** (calibrate) and then **step 9** — make sure their `~/.claude/CLAUDE.md` has the
`How to explain things to me` section matching the level they just gave (they may not have it yet,
or it may be stale); seed or refresh it, showing the diff first. Then go straight to **step 12**,
which runs in every case.

### 2. Calibrate — "how should I pitch this?"  *(runs in every case)*

Now that you've seen the audit, find out who you're talking to so the rest of this setup — and
every future session — lands at the right depth. Use **AskUserQuestion** (single-select) with the
four rungs from [`references/explanation-levels.md`](references/explanation-levels.md), worded in
plain words:

1. New to all this — computers included
2. Comfortable with computers, but I've never coded
3. I can code a bit — still learning
4. I code confidently

The audit gives you a hint — existing `git_identity`, `gh_auth`, or `mise` means they're almost
certainly not rung 1 — so pre-bias your framing, but still ask; don't assume. Then invite a
**one-line free-text reply**: "tell me a bit about your background and how you like things
explained — e.g. have you used AI to write code before, any languages you already know?" That
elaboration (and whether they've used AI to code) is the most useful signal — capture it.

This answer drives two things: how you explain the rest of *this* walkthrough, and the
`## How to explain things to me` section you'll seed into their global CLAUDE.md in **step 9**
(date-stamped so it self-renews ~monthly). Keep the picked rung and their free-text in mind for
both.

### 3. mise — the toolchain backbone

Everything in the CLI column flows through [mise](https://mise.jdx.dev), so upgrades are one
command forever after. If `mise=missing`, install it (confirm first — it modifies the shell
profile):

```bash
curl https://mise.run | sh        # then add the shown `mise activate` line to the shell rc
```

Then pin the global tools (idempotent — re-running just re-resolves):

```bash
mise use -g node@lts pnpm python uv jq ripgrep gitleaks github-cli \
  fd bat eza zoxide fzf delta lazygit yq hyperfine
```

`github-cli` provides `gh`. The second line is a set of modern command-line tools that make
everyday work faster and friendlier — better `find`/`grep`/`ls`/`cat`, fuzzy search, a nicer
git diff, and a visual git UI. Each is explained in plain language in
[`references/tools.md`](references/tools.md); install them via mise (not the system package
manager — apt ships stale versions and renames some, e.g. `fd`→`fdfind`, `bat`→`batcat`).

With mise already present and tools installed, **upgrade the behind ones** instead:

```bash
mise outdated        # show what's behind
mise upgrade         # bring everything current (respects the lockfile / release-age cooldown)
```

> Tell the user to open a **new terminal** (or `source` their rc) after the first mise install
> so the tools land on `PATH`. Re-run the audit to confirm.

### 4. GitHub — account, login, identity

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

### 5. VS Code + the Claude Code extension  *(confirm — GUI install)*

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

### 6. Docker  *(confirm — heavy / licensed)*

If `docker=missing`, confirm before installing — it's large and Docker Desktop has licensing
terms for big companies:

- **macOS / Windows(WSL):** Docker Desktop (download, or `brew install --cask docker` on macOS).
- **Linux:** Docker Engine via the official convenience script (`curl -fsSL
  https://get.docker.com | sh`) — this needs `sudo` **and** pipes a remote script to a shell,
  so explain it and get explicit approval, then add them to the `docker` group.

Verify with `docker run hello-world`. Pair this with the bundled [[dockerfile]] skill when they
write their first Dockerfile.

### 7. Playwright browsers

The agent uses Playwright to open a real browser and screenshot the app (drives the [[verify]]
and `run` workflows, and is **required by vischeck**). With `uv` present:

```bash
uvx playwright install chromium       # idempotent; re-run after Playwright upgrades
```

On Linux/WSL add `--with-deps` if a launch complains about missing system libraries (needs
`sudo` — confirm). For JS projects that bundle Playwright, the project-local path is `npx
playwright install`.

### 8. Plugins

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
  the guard's commit-to-main check is what `DEV_HOOKS_GUARD_MAIN` in step 9 switches on).
- **thinking-tools** — pushback on demand: adversarial critique (board), premortems, and
  "did you actually run it?" checks (but-for-real, self-rate).
- **writing** — README structure, readability, and de-AI-ing prose (github-readme,
  readability, humanizer).
- **Superpowers** — an agentic skills/methodology framework.
- **vischeck** — visual UI verification (authenticated screenshots + a review rubric); it needs
  `uv` and the chromium browser from step 7, both already set up.

### 9. Seed Claude config  *(confirm — writes ~/.claude)*

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
2. **Global CLAUDE.md defaults** — safe working rules (plan big tasks first, keep changes small
   and committed, never commit secrets, confirm before destructive ops). Start from
   [`references/templates/CLAUDE.defaults.md`](references/templates/CLAUDE.defaults.md), but
   **before** writing it, replace its `## How to explain things to me` section with the rung the
   user picked in step 2: take the matching block from
   [`references/explanation-levels.md`](references/explanation-levels.md), weave in their
   free-text reply, and stamp the footer with **today's date** (this is what makes the comfort
   check-in recur ~monthly). **Drop the `<!-- … -->` marker comment** — it's a note to you, not
   for their file. Then copy to `~/.claude/CLAUDE.md`, or merge into an existing one. Everything
   else in the template is the same for everyone — only that one section changes.

See [`references/claude-config.md`](references/claude-config.md) for how these two work together
with the dangerous-command guard (config sets expectations; the hook enforces at runtime).

### 10. Orient — Git

Everyone touches **Git** constantly. If the user is on a lower rung (step 2) or says they're new
to it, give the short tour from [`references/git-basics.md`](references/git-basics.md) — the
everyday loop, branches & pull requests, and how to undo mistakes safely. For an experienced user
who already knows Git, skip the tour — just confirm their identity is set. Don't lecture — point
them there and answer questions.

[`references/tools.md`](references/tools.md) explains, in plain language, what every tool is and
why it's there — link it for the curious.

### 11. Verify + report

Re-run the audit and report real results, not assumptions:

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/getting-started/scripts/onboard_check.sh"
```

Confirm each line that was `missing` is now `installed`, `gh_auth=yes`, `git_identity=yes`, and
`playwright_browsers=installed`. List anything still outstanding (e.g. a GUI install the user
declined, or a `sudo` step they need to run themselves) and what's left for them to do.

### 12. Always end here — "so, what do you want to do?"  *(never skip)*

**This step runs every time, no matter what the audit showed.** Setup is the means, not the
point — someone whose machine was already perfect still came here wanting to *do something*.
So when nothing needed installing (everything `installed` on the first audit), don't stop with
"you're all set!" and end the turn — go straight here.

Ask the user — use **AskUserQuestion** so it's a real choice, not a wall of text — what they're
here to do, and route to the skill that owns it:

- **Build something** (an app, a website, a tool) → hand off to **[[starting-a-project]]**: a
  "what are you building?" decision tree that picks a stack (Astro, React + Vite, Rails/Django,
  FastAPI, Python + uv, Expo, Streamlit) and walks them through putting it online. Don't
  duplicate that decision tree here — invoke the skill.
- **Solve a specific problem / improve something that already exists** → if it's an existing
  codebase, offer **[[dev-env-setup]]** to bring the repo up to the lint/test/CI/secrets
  standard; if it's a fresh idea, that's really "build something" → starting-a-project.
- **Automate a repetitive task** (a chore they do by hand a lot) → help them name the task,
  then route: **[[weekly-automation-review]]** to spot what's worth automating, and a hook or
  skill to do it — the `dev-hooks` plugin for automatic guardrails, or **[[skill-creator]]** to
  package a repeatable workflow into a skill.
- **Just exploring / not sure yet** → suggest a tiny first project (a one-page site or a small
  script) via starting-a-project so they get the build-run-ship loop end to end once.

Keep your own framing short and in plain words; let the handed-off skill carry the depth. The
goal of getting-started is met not when the tools are installed, but when the user is pointed at
their actual next move.

## Notes

- **Never auto-run the destructive/confirm steps.** sudo, Docker, VS Code, the mise profile
  edit, `~/.claude` writes, and `--with-deps` all wait for explicit user approval.
- This skill bootstraps a *machine*. To bring a *repo* up to the full mise/hk/CI/gitleaks
  standard, that's the separate [[dev-env-setup]] skill — mention it once they have a project,
  don't run it here.
- `troubleshooting.md` collects the common stumbles (PATH after mise install, no Homebrew, WSL
  not enabled, `gh auth` loops, `code` CLI missing on macOS) — check it before improvising.
