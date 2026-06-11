# Picking what to build with

When someone's starting a new project, the first question isn't "which framework" — it's **what
are you building?** Answer that and the choice is usually obvious. Three common cases cover most
beginners. Pick the simplest one that fits; you can always grow into something bigger later.

> Match the framework to the **deploy target** too — see [`deploy.md`](deploy.md). A static site
> goes almost anywhere (including free GitHub Pages); an app that runs a server needs a host that
> runs servers.

## 1. A content website → **Astro**

A blog, portfolio, landing page, documentation, or any site that's mostly pages and content.

[Astro](https://astro.build) is the best default here: it ships **zero JavaScript by default**
(so the site is fast), has first-class Markdown/MDX for content, and is genuinely beginner
-friendly. It builds to plain static files, so it deploys anywhere — including **GitHub Pages**
for free.

```bash
pnpm create astro@latest      # scaffold; then `pnpm dev` to run it locally
```

Need a *bit* of interactivity (a search box, a carousel)? Astro lets you drop in a React/Vue/Svelte
"island" just for that part, without turning the whole site into an app. Reach for option 2 only
when *most* of the page is interactive.

**Deploy:** GitHub Pages, Cloudflare Pages, Netlify, or Vercel.

## 2. An interactive app → **React + Vite**  (or Next.js if it needs a server)

A dashboard, an editor, a tool — something where the page is mostly live, stateful UI.

[React](https://react.dev) scaffolded with [Vite](https://vite.dev) is the modern, no-magic
default for this:

```bash
pnpm create vite@latest my-app -- --template react-ts   # then `pnpm install && pnpm dev`
```

One thing to know: React + Vite builds a **client-only** app (a "single-page app"). It renders in
the browser, which is great for tools behind a login, but it has **no server-side rendering or
SEO** on its own. If the project needs to be indexed by search engines, render on the server, or
bundle a backend with the frontend, that's when [Next.js](https://nextjs.org) (`pnpm create
next-app`) earns its extra complexity — otherwise stick with the simpler Vite setup.

**Deploy:** the Vite build is static → same hosts as option 1. A Next.js app (server-rendered) is
happiest on **Vercel**.

## 3. An API / backend → **FastAPI**

A backend service: data, accounts/auth, talking to other services, or the API behind a mobile or
frontend app.

[FastAPI](https://fastapi.tiangolo.com) is the default here, and it pairs perfectly with the
Python + `uv` we already set up — type-driven, with **automatic interactive API docs** at
`/docs`:

```bash
uv init my-api && cd my-api
uv add "fastapi[standard]"
fastapi dev main.py           # runs with auto-reload; docs at http://127.0.0.1:8000/docs
```

If you're firmly a JavaScript person rather than Python, [Hono](https://hono.dev) or Express are
the JS equivalents — but default to FastAPI.

**Deploy:** an API runs a server, so it needs a host that runs servers — **Railway, Render, or
Fly.io**, *not* GitHub Pages. (See [`deploy.md`](deploy.md).)

## Still not sure?

- It's mostly words and pictures → **Astro**.
- It's a clickable app with lots of live state → **React + Vite**.
- It has no UI, or it's the data/logic behind one → **FastAPI**.
- It's a mix → start with the front end (Astro or React) and add a FastAPI backend when you
  actually need one. Don't build all three on day one.
