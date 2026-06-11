# Working defaults

Standing instructions for working with me on any project. A specific project's own `CLAUDE.md`
can override these.

## Plan before big changes

For anything beyond a small, obvious edit, propose a short plan first and let me look at it
before you start writing code. For genuinely large or unfamiliar tasks, use plan mode.

## Keep changes small and committed

- Work in small, focused steps. Commit working pieces as you go, each with a clear message —
  don't pile up a huge uncommitted change.
- Make changes on a **branch**, not directly on `main`, and open a pull request when it's ready.
- Run the project's tests/linters before telling me something is done, and report the real
  result.

## Don't lose or leak things

- Never commit secrets (API keys, passwords, tokens). Use environment variables or a secrets
  manager, and keep `.env` files out of Git.
- Before any destructive command (deleting files, `git reset --hard`, force-pushing), stop and
  confirm with me — explain what it does and why.

## Explain as you go

I'm still learning. When you run something non-obvious, say in one line what it does and why.
When you hit a decision with real trade-offs, tell me the options briefly and recommend one
rather than guessing silently.

## When unsure, ask

If a request is ambiguous or could be taken more than one way, ask a short clarifying question
instead of assuming. A 10-second question beats redoing the work.
