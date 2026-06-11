# What each tool is, and why it's here

Plain-language tour of everything the setup installs. You don't need to understand all of it to
start — come back when you're curious about a name you keep seeing.

## The editor and the agent

- **VS Code** — the code editor. Where you read and write files, see the project, and run
  things. Free, from Microsoft.
- **Claude Code** — the AI agent (this!). Reads your code, makes changes, runs commands. You
  already have it; setup just makes sure it's current.
- **Claude Code VS Code extension** — runs Claude *inside* VS Code, so you can review its plans
  and see edits applied inline instead of switching to a terminal.

## The toolchain manager

- **mise** — installs and version-manages your developer tools from one config. Instead of
  installing Node, Python, etc. five different ways, mise installs them all and keeps them
  current with `mise upgrade`. It's why this whole setup stays easy to update.

## Languages and package managers

- **Node.js** — runs JavaScript outside the browser. Most web tooling needs it.
- **pnpm** — installs JavaScript packages (libraries) for a project. Like a faster, tidier npm.
- **Python** — a general-purpose language, common for scripts, data, and backends.
- **uv** — installs Python packages and manages Python environments. Fast, modern, and the
  default this ecosystem uses. It can also run a script with its dependencies in one go
  (`uvx`).

## Command-line helpers

- **git** — version control: saves and shares every version of your project. See
  [`git-basics.md`](git-basics.md).
- **gh** — GitHub's command-line tool: log in to GitHub, open pull requests, and let `git push`
  authenticate without fuss.
- **jq** — reads and filters JSON on the command line. Several dev-hooks scripts rely on it.
- **ripgrep (`rg`)** — searches your code fast. Claude uses it constantly to find things.
- **gitleaks** — scans your project for accidentally-committed secrets (API keys, passwords)
  before they leak. A safety net that pairs with the secret-reminder hook.

## Running and testing apps

- **Docker** — packages an app with everything it needs so it runs the same anywhere. Useful
  for databases and for deploying. Heavier than the rest, so setup asks before installing it.
- **Playwright (browsers)** — drives a real browser automatically. Lets the agent open your app,
  click around, and take screenshots to check a change actually works.

## Claude Code plugins

- **dev-hooks** — your safety net while coding with an agent: auto-formats files, runs your
  tests before finishing, reminds about secrets and missing tests, and **guards against
  dangerous commands** (see [`claude-config.md`](claude-config.md)).
- **Superpowers** — a framework of extra skills and a development methodology for the agent.
- **vischeck** — visual checking: takes authenticated screenshots of your UI and reviews them
  against a quality rubric, so visual changes get a real look, not just a "looks fine".

## What you do NOT need yet

Kubernetes, cloud accounts beyond GitHub, custom domains, CI/CD pipelines, a dozen VS Code
extensions. Start with the above. Add things when a real need shows up, not before.
