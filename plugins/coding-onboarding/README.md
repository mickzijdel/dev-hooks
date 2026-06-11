# coding-onboarding

A Claude Code plugin for people new to coding (or to AI-assisted coding): one skill sets up
their machine, the other helps them pick a stack and get a first project online. Built to be
handed to someone you're onboarding without also subjecting them to a full hook suite —
though `getting-started` recommends the sibling plugins from the same marketplace once the
basics are in place.

Part of the [dev-hooks marketplace](../../README.md), alongside `dev-hooks`,
`thinking-tools`, and `writing`.

## Skills

| Skill | Use when |
|-------|----------|
| `getting-started` | Setting up a brand-new machine for AI-assisted coding (or bringing an existing setup up to date) — idempotently installs/upgrades a baseline toolchain via mise (node/pnpm/Python + uv, jq, ripgrep, gitleaks, gh), VS Code + the Claude Code extension, Docker, the Playwright browsers, and the dev-hooks/thinking-tools/writing/Superpowers/vischeck plugins; sets up a GitHub account + git identity; seeds beginner-safe Claude config (a permissions allowlist + CLAUDE.md defaults); orients first-timers on Git; and hands off to `starting-a-project` once they're ready to build. Detect-and-confirm: it pauses before sudo, GUI installs, and `~/.claude` writes. macOS, Linux, and WSL2. |
| `starting-a-project` | Deciding what to build a new project with and getting it online — a "what are you building?" decision tree mapping common beginner goals to a concrete stack (a content website → Astro; an interactive app → React + Vite/Next.js; a database-backed web app → Rails/Django; an API → FastAPI; a script/automation → Python + uv; a phone app → Expo; a data dashboard → Streamlit; plus desktop/game/extension/bot), each with a scaffold command, styling (Tailwind, shadcn/ui), database and auth pointers, and a matching deploy target. Then a deploy guide from static sites (GitHub Pages) through full-app hosts and containers. Use for "what should I use to build X?" or "how do I put this online?". Companion to `getting-started`. |

## Install

```bash
/plugin marketplace add mickzijdel/dev-hooks
/plugin install coding-onboarding@dev-hooks
```

## Notes

- The `getting-started` skill bootstraps a *machine* (not a repo): it ships an idempotent audit
  script (`scripts/onboard_check.sh`, read-only — detects, never installs) and a prose workflow
  that installs/upgrades only what's missing, pausing for confirmation before any sudo, GUI
  install, or `~/.claude` write. Its Claude-config templates (`references/templates/`) are seeded
  via the `update-config` skill, and it points first-timers at a bundled Git reference and, once
  they're ready to build, hands off to the `starting-a-project` skill. It targets macOS, Linux,
  and WSL2 (bash); on native Windows it sets up WSL2 first. Companion to the `dev-hooks` plugin's
  dangerous-command guard, which enforces at runtime what the seeded CLAUDE.md defaults ask for.
- The `starting-a-project` skill is the build-and-ship companion to `getting-started`: a
  "what are you building?" decision tree (`references/starter-stacks.md`) mapping each common
  beginner goal to a stack + scaffold command, and a deploy guide (`references/deploy.md`) from
  static sites through full-app hosts and containers. It's advisory — Claude reads it to
  recommend, and may run the scaffold command — and stays framework-agnostic, steering to the
  simplest option that fits.
