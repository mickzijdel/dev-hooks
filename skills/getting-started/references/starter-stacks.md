# Picking what to build with

When someone's starting a new project, the first question isn't "which framework" — it's **what
are you building?** Answer that and the choice is usually obvious. Four common cases cover most
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
pnpm astro add mdx tailwind    # MDX content + Tailwind styling (see "things you'll need" below)
```

Write your pages in **MDX** (`.mdx`) — it's Markdown that can also use components, so a content
site stays easy to write but isn't limited to plain prose. For styling the rendered Markdown, add
Tailwind's typography plugin (`pnpm add -D @tailwindcss/typography`) and wrap your content in
`<article class="prose">` — that one class gives headings, lists, links, and code blocks sensible
defaults so a blog post looks good with zero hand-written CSS.

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

For styling and components, add **Tailwind** and then **[shadcn/ui](https://ui.shadcn.com)**
(`pnpm dlx shadcn@latest init`, then e.g. `pnpm dlx shadcn@latest add button`). shadcn isn't a
dependency you install — it *copies* accessible, good-looking components (buttons, dialogs, forms)
straight into your project so you own and can edit them. It's the fastest way for a beginner to get
a polished React/Next.js UI without designing one from scratch.

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

## 4. A full database-backed web app → **Rails** (or Django)

One framework that does the *whole* app: server-rendered pages, a database, forms, user accounts,
an admin area — the classic "sign up, log in, create / edit / list your stuff" product.

This is exactly what **[Ruby on Rails](https://rubyonrails.org)** is built for, and it's genuinely
one of the friendliest ways to build a real app: strong conventions mean far fewer decisions and
less wiring, scaffolding generates a working create/read/update/delete screen in a single command,
and **Hotwire** gives you live interactivity without standing up a separate JavaScript front end.
(The JavaScript world's "tide" is about *front-end* frameworks — it takes nothing away from Rails
as a full-stack monolith, which is as capable as ever.)

```bash
mise use ruby@latest          # Rails needs Ruby, which the skill doesn't install by default
gem install rails && rails new my-app && cd my-app
bin/rails generate scaffold post title:string body:text   # a full CRUD screen, instantly
bin/rails server              # http://localhost:3000
```

Prefer to stay in Python with no new language to install? **[Django](https://www.djangoproject.com)**
is the equivalent — same batteries-included, admin-out-of-the-box philosophy — and it pairs with
the `uv` setup (`uv add django`).

**Deploy:** runs a server *and* a database → **Railway, Render, or Fly.io** (see
[`deploy.md`](deploy.md)).

## A few things you'll probably need

Whatever you pick above, these come up fast — reach for the boring, standard answer:

- **Styling → [Tailwind](https://tailwindcss.com).** Utility classes you write in your markup
  instead of separate CSS files. It works with all four options and is the default the rest of
  this guide assumes. For long-form content, add the typography plugin and use `prose` (see Astro
  above).
- **Polished components (React / Next.js) → [shadcn/ui](https://ui.shadcn.com)** (see option 2).
- **A database → start with [SQLite](https://www.sqlite.org).** It's just a file, with zero setup,
  and it's plenty for learning and small apps (Rails and Django use it by default). Switch to
  **PostgreSQL** when you outgrow it — your framework makes that a config change, not a rewrite.
- **Logins → don't roll your own.** Auth is easy to get subtly wrong. Use the framework's built-in
  solution (Rails 8 ships one; Django has `django.contrib.auth`) or a service like
  [Clerk](https://clerk.com), [Supabase](https://supabase.com), or
  [Auth.js](https://authjs.dev) for SPA / Next.js apps.

## Still not sure?

- It's mostly words and pictures → **Astro**.
- It's a clickable app with lots of live state → **React + Vite**.
- It's a "sign up and manage your stuff" app with a database → **Rails** (or Django).
- It has no UI of its own, or it's the data/logic behind one → **FastAPI**.
- It's a mix → start with the one piece you need first and add the others when you actually need
  them. Don't build all of it on day one.
