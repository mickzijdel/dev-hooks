---
name: starting-a-project
version: 1.0.0
description: |
  Help someone decide what to build a new project with, and get it online. A "what are you
  building?" decision tree that maps the common beginner goals — a content website, an interactive
  app, a database-backed web app, an API, a script or automation, a phone app, a data dashboard —
  to a concrete framework (Astro, React + Vite / Next.js, Rails / Django, FastAPI, Python + uv,
  Expo, Streamlit), each with a scaffold command and a matching deploy target. Also covers styling
  (Tailwind, shadcn/ui), databases, auth, and how to put it online (GitHub Pages → full-app hosts
  and containers). Use when someone asks "what should I use to build X?", "how do I start a new
  project?", or "how do I deploy / put this online?".
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - WebFetch
---

# starting-a-project

Two questions when someone wants to build something new: **what to build it with**, and **how to
get it online**. Answer the first from *what they're building*, not from a favourite framework —
then pick the simplest option that fits. They can always grow into something bigger later.

## Pick a stack — what are you building?

| What you're building | Start with |
|----------------------|-----------|
| A content website (blog, portfolio, docs, landing page) | **Astro** |
| An interactive app (dashboard, editor, tool) | **React + Vite** — Next.js if it needs a server |
| A database-backed web app (sign up, log in, CRUD your stuff) | **Rails** (or **Django**) |
| An API / backend service | **FastAPI** |
| A script, tool, or automation | **Python + uv** (or whatever's lightest) |
| A phone app | **Expo** (React Native) |
| A data app or dashboard | **Streamlit** |
| A desktop app, game, browser extension, or chat bot | see the catch-all in the full guide |

The full guide — scaffold command for each, plus styling (**Tailwind**, **shadcn/ui**),
databases (start with **SQLite**), auth, and every option's deploy target — is in
[`references/starter-stacks.md`](references/starter-stacks.md). Read it before recommending one;
don't reconstruct it from memory.

## Ship it — how to put it online

Once it works locally and they ask "how do people actually put this on the internet?", use
[`references/deploy.md`](references/deploy.md): a decision guide from static sites (**GitHub
Pages** is the free starting point) through full-app hosts and containers, each with a
one-command path.

Stack and deploy target are linked, so the two halves connect: anything that builds to **static
files** (Astro, a Vite build) goes almost anywhere; anything that **runs a server** (Next.js,
Rails/Django, FastAPI, Streamlit) needs a host that runs servers (Railway, Render, Fly.io); a
**phone app** ships through the app stores via EAS.

## Notes

- Recommend the *simplest* thing that fits — a beginner shipping a static Astro site beats one
  stalled on a Next.js + database setup they don't need yet. Suggest growing into more only when
  the project actually calls for it.
- This skill is about choosing and shipping. Setting up the *machine* it runs on (toolchain,
  editor, Git identity, Claude config) is the separate [[getting-started]] skill.
