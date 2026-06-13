# What each tool is, and why it's here

Plain-language tour of everything the setup installs. You don't need to understand all of it to
start — come back when you're curious about a name you keep seeing. If a word here is new (what
*is* a "package manager"?), the one-line glossary in [`plain-words.md`](plain-words.md) explains
the jargon first.

Each entry also says **why this one** and not a popular alternative — so when you read about a
different tool online, you know what trade-off we made for you.

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
  *Why mise?* The older way was a separate installer per language (nvm for Node, pyenv for
  Python, and so on) — five things to learn and update. mise replaces all of them with one, and
  pins exact versions so your machine matches the project.

## Languages and package managers

- **Node.js** — runs JavaScript outside the browser. Most web tooling needs it.
- **pnpm** — installs JavaScript packages (libraries) for a project. Like a faster, tidier npm.
  *Why pnpm over npm?* npm comes with Node and works fine; pnpm does the same job but is faster
  and stores each library once on disk instead of re-copying it into every project.
- **Python** — a general-purpose language, common for scripts, data, and backends.
- **uv** — installs Python packages and manages Python environments. Fast, modern, and the
  default this ecosystem uses. It can also run a script with its dependencies in one go
  (`uvx`).
  *Why uv?* The traditional Python setup is three separate tools (`pip` to install, `venv` for
  environments, `pyenv` for versions). uv does all three, and is dramatically faster — one tool
  to learn instead of three.

## Command-line helpers

- **git** — version control: saves and shares every version of your project. See
  [`git-basics.md`](git-basics.md).
- **gh** — GitHub's command-line tool: log in to GitHub, open pull requests, and let `git push`
  authenticate without fuss. *Why gh?* You can do all of this on the GitHub website by hand, but
  `gh` lets Claude do it for you from the terminal — and handles the login so `git push` just
  works instead of asking for a password every time.
- **jq** — reads and filters JSON on the command line. Several dev-hooks scripts rely on it.
- **ripgrep (`rg`)** — searches your code fast. Claude uses it constantly to find things.
- **gitleaks** — scans your project for accidentally-committed secrets (API keys, passwords)
  before they leak. A safety net that pairs with the secret-reminder hook.

## Running and testing apps

- **Docker** — packages an app with everything it needs so it runs the same anywhere. Useful
  for databases and for deploying. Heavier than the rest, so setup asks before installing it.
  *Which Docker?* On a laptop the easy choice is **Docker Desktop** (an app with a dashboard);
  it's what setup points you to. Servers use the leaner **Docker Engine** under the hood — same
  idea, no GUI. You want Desktop on your own machine.
- **Playwright (browsers)** — drives a real browser automatically. Lets the agent open your app,
  click around, and take screenshots to check a change actually works.

## Claude Code plugins

- **dev-hooks** — your safety net while coding with an agent: auto-formats files, runs your
  tests before finishing, reminds about secrets and missing tests, and **guards against
  dangerous commands** (see [`claude-config.md`](claude-config.md)).
- **thinking-tools** — same marketplace as dev-hooks: skills that push back — adversarial
  critique, premortems, and "did you actually run it?" self-checks.
- **writing** — same marketplace: README structure, readability, and making prose sound
  less AI-generated.
- **Superpowers** — a framework of extra skills and a development methodology for the agent.
- **vischeck** — visual checking: takes authenticated screenshots of your UI and reviews them
  against a quality rubric, so visual changes get a real look, not just a "looks fine".

## What you do NOT need yet

Kubernetes, cloud accounts beyond GitHub, custom domains, CI/CD pipelines, a dozen VS Code
extensions. Start with the above. Add things when a real need shows up, not before.
