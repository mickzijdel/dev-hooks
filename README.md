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
| [`dev-hooks`](plugins/dev-hooks/) | Polyglot dev-workflow hooks — auto-lint on edit, verify tests/linters before stopping, a dangerous-command guard, per-prompt logging that feeds the weekly automation review, and a set of advisory reminder hooks (secrets, debug leftovers, TODO/FIXME leftovers, missing tests, Dockerfiles, popovers, migration safety, accessibility, SQL injection, swallowed errors, CI action refs, inline SVG, scaffolding, dependency staleness, big uncommitted changes, …), plus a self-stocking/self-advertising personal CLI-script library (a SessionStart index of your saved tools + an end-of-session nudge to keep reusable one-offs) — plus the companion skills the hooks point at: `dev-env-setup`, `github-actions`, `dependency-upgrade`, `env-to-fnox`, `dockerfile`, `popovers-tooltips`, `tailwind`, `accessibility`, `worktree-setup`, `repo-review`, `script-library`. |
| [`coding-onboarding`](plugins/coding-onboarding/) | For people new to coding or AI-assisted coding: `getting-started` (idempotent machine setup — toolchain incl. modern CLI tools, VS Code, Docker, GitHub, the AGENTS.md/CLAUDE.md symlink convention; asks the user's experience level and calibrates the seeded Claude config to it, with a self-renewing monthly comfort check-in) and `starting-a-project` (a "what are you building?" stack decision tree with scaffold commands and deploy targets). |
| [`thinking-tools`](plugins/thinking-tools/) | Critique and self-checking skills: `board`, `premortem`, `but-for-real`, `self-rate`, `code-simplifier`, `weekly-automation-review`, `commit-digest`, `adr`. |
| [`writing`](plugins/writing/) | Writing/content skills: `github-readme`, `humanizer`, `readability` (adapted from [Nate Berkopec's dotfiles](https://github.com/nateberkopec/dotfiles)) and `voice-profile` (match a person's writing voice from a profile of their own rules) — plus `readme-reminder` and `voice-reminder` hooks that audit READMEs and check prose against a voice profile on write. |

Each plugin's README documents its contents, env vars, and notes.

## Installation

### Never coded before? One command does everything

If you don't have Claude Code yet, this single line installs it, signs you in, installs the
onboarding plugin, and opens a checklist (a small window you can keep on top of your other
windows) that explains each step as it happens. Paste it into a terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/mickzijdel/dev-hooks/main/install.sh | bash
```

When it finishes, type `claude`, press Enter, and say **set me up** — Claude takes over from
there. Works on macOS, Linux, and WSL2; on Windows the checklist walks you through enabling
WSL2 first. See [coding-onboarding](plugins/coding-onboarding/README.md) for what it does and
the available options.

### Already have Claude Code

Add the marketplace once, then install the plugins you want:

```bash
/plugin marketplace add mickzijdel/dev-hooks
/plugin install dev-hooks@dev-hooks
/plugin install coding-onboarding@dev-hooks
/plugin install thinking-tools@dev-hooks
/plugin install writing@dev-hooks
```

## Usage

Everything runs inside Claude Code. The `dev-hooks` hooks fire automatically — lint after
edits, verify tests before stopping, guard dangerous commands. Skills trigger on matching
tasks, or invoke one directly:

```console
$ claude
> /dev-hooks:dev-env-setup audit this repo against the dev-env standard
```

## Local development

Clone the repo, add the working copy as a local marketplace, and install from it:

```bash
git clone https://github.com/mickzijdel/dev-hooks ~/Stack/Programmeren/dev-hooks
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

## License

[MIT](LICENSE)
