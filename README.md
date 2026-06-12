# dev-hooks (marketplace)

> [!TIP]
> Also check out [vischeck](https://github.com/mickzijdel/vischeck) (screenshot-based visual
> verification for agents) and [rails-toolkit](https://github.com/mickzijdel/rails-toolkit)
> (agent skills for Rails 8+). You might also like my other plugins, such as
> [readoc](https://github.com/mickzijdel/readoc) (read/edit .docx, .xlsx, and PDFs) and
> [airtable-utils](https://github.com/mickzijdel/airtable-utils) (Airtable scripting and
> schema tools).

A Claude Code plugin marketplace serving four plugins from this one repo. Install only what
fits your use: the hook suite for day-to-day agent coding, the onboarding skills for someone
new to coding, or the thinking/writing toolkits anywhere.

## Plugins

| Plugin | What it is |
|--------|------------|
| [`dev-hooks`](plugins/dev-hooks/) | Polyglot dev-workflow hooks — auto-lint on edit, verify tests/linters before stopping, a dangerous-command guard, and a set of advisory reminder hooks (secrets, debug leftovers, missing tests, Dockerfiles, popovers, CI action refs, inline SVG, scaffolding, dependency staleness, big uncommitted changes, …) — plus the companion skills the hooks point at: `dev-env-setup`, `env-to-fnox`, `dockerfile`, `popovers-tooltips`. |
| [`coding-onboarding`](plugins/coding-onboarding/) | For people new to coding or AI-assisted coding: `getting-started` (idempotent machine setup — toolchain, VS Code, Docker, GitHub, beginner-safe Claude config) and `starting-a-project` (a "what are you building?" stack decision tree with scaffold commands and deploy targets). |
| [`thinking-tools`](plugins/thinking-tools/) | Critique and self-checking skills: `board`, `premortem`, `but-for-real`, `self-rate`, `code-simplifier`, `weekly-automation-review`, `commit-digest`. |
| [`writing`](plugins/writing/) | Writing/content skills adapted from [Nate Berkopec's dotfiles](https://github.com/nateberkopec/dotfiles): `github-readme`, `humanizer`, `readability`. |

Each plugin's README documents its contents, env vars, and notes.

## Install

Add the marketplace once, then install the plugins you want:

```bash
/plugin marketplace add mickzijdel/dev-hooks
/plugin install dev-hooks@dev-hooks
/plugin install coding-onboarding@dev-hooks
/plugin install thinking-tools@dev-hooks
/plugin install writing@dev-hooks
```

## Migrating from 1.x

Before v2, this repo was a single `dev-hooks` plugin at the repo root.

- `/plugin install github:mickzijdel/dev-hooks` **no longer works** — the repo root is now a
  marketplace, not a plugin. Reinstall via the marketplace commands above.
- A symlink of the **repo root** into `~/.claude/skills/` (the old local-dev trick) breaks
  **silently** — the root no longer has a plugin manifest or `skills/`/`hooks/` dirs. Remove
  it and use one of the local-development options below.
- Marketplace installs of `dev-hooks@dev-hooks` keep working: refresh the marketplace
  (`/plugin marketplace update dev-hooks`) and update the plugin.
- Skills that moved to a sibling plugin have new qualified names, e.g.
  `dev-hooks:premortem` → `thinking-tools:premortem`,
  `dev-hooks:getting-started` → `coding-onboarding:getting-started`,
  `dev-hooks:humanizer` → `writing:humanizer`. The four skills still in `dev-hooks`
  (`dev-env-setup`, `env-to-fnox`, `dockerfile`, `popovers-tooltips`) are unchanged.

## Local development

Add the working copy as a local marketplace and install from it:

```bash
/plugin marketplace add ~/Stack/Programmeren/dev-hooks
/plugin install dev-hooks@dev-hooks   # and the others as needed
```

Alternatively each plugin directory is itself a valid "skills-directory plugin" and can be
symlinked into `~/.claude/skills/` (run `/reload-plugins` to pick up changes):

```bash
ln -s ~/Stack/Programmeren/dev-hooks/plugins/dev-hooks ~/.claude/skills/dev-hooks
```

> ⚠️ Do **not** symlink AND marketplace-install the same plugin on the same machine — the
> hooks would fire twice. Use one mechanism on your dev machine and the marketplace install
> elsewhere.

## Development

One repo-wide toolchain covers all four plugins: `mise` pins the tools, `hk` runs the
pre-commit checks (shellcheck, shfmt, ruff, vulture, jscpd, gitleaks, plus
`claude plugin validate --strict` over the marketplace and every plugin when plugin files
are staged), and CI mirrors the same checks (except plugin-validate, which needs the Claude
CLI and runs locally only). The pytest suite at `tests/` exercises every hook and skill
script across all plugins.

```bash
mise install
uv run pytest -q
hk check
```
