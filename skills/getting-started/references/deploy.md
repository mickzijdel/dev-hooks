# Putting your app online

"Deploying" means getting your project off your laptop and onto the internet so others can use
it at a URL. Where you deploy depends on **what kind of thing you built**. Start by answering
one question:

> **Does it have a backend** — a server, a database, logins, anything that runs code *after* the
> page loads? Or is it just files a browser can open (HTML, CSS, JavaScript, images)?

- **Just files (a "static site")** → start with **GitHub Pages** (free, below).
- **Has a backend** → jump to [Full apps](#full-apps-has-a-backend).
- **You wrote a Dockerfile** → [Containers](#containers-you-have-a-dockerfile).

## Static sites

A static site is HTML/CSS/JS with no server behind it — a landing page, a portfolio, docs, or a
frontend framework's built output. The easiest free option:

### GitHub Pages  — the free starting point

You already have a GitHub account from setup, so there's nothing new to install. Push your site
to a repo, turn Pages on in **Settings → Pages**, pick the branch, and GitHub serves it at
`https://<username>.github.io/<repo>`.

Two things to know before you choose it:

- **Static only.** GitHub Pages serves files. It cannot run a backend, a database, or
  server-side code. If your app needs those, use a full-app host below.
- **Free accounts must be public.** On the free GitHub plan, Pages only publishes from a
  **public (open-source) repository** — anyone can read your code. To keep the source private
  and still publish, you need a paid GitHub plan, or use one of the hosts below (most have a
  free tier that works from private repos).

Other static hosts, if you outgrow Pages or want a private repo for free:
**Cloudflare Pages**, **Netlify**, **Vercel** — all connect to your GitHub repo and redeploy
automatically on every push, from public *or* private repos. Typical first deploy:

```bash
npm i -g vercel && vercel        # or: netlify deploy ; or connect the repo in the web dashboard
```

## Full apps (has a backend)

If your app runs code on a server — an API, a database, user accounts — you need a host that
runs your backend, not just files:

- **Vercel** — best for Next.js and frontend-heavy apps with light backend functions.
- **Railway** / **Render** — friendly for a typical web app + database; connect the repo, they
  build and run it. Good first choice for beginners.
- **Fly.io** — runs your app close to users; works straight from a Dockerfile.

These connect to your GitHub repo and redeploy on push. Each has a CLI you can install **when
you pick one** (don't install all of them):

```bash
mise use -g flyctl        # Fly.io        →  fly launch
# Railway/Render/Vercel:  connect the repo in their web dashboard, or use their CLI
```

## Containers (you have a Dockerfile)

If you've containerised the app (see the **dockerfile** skill), you can ship that image:

- **Fly.io** (`fly launch` detects the Dockerfile) and **Render** both deploy directly from a
  Dockerfile — no separate registry needed to start.
- For more control, push the image to a registry (GitHub Container Registry, Docker Hub) and run
  it on any container host.

## A sane first deploy

1. Get it working locally first.
2. Push to GitHub (a clean repo with a README).
3. Pick the simplest host that fits the table above — for a static site, that's GitHub Pages.
4. Deploy, open the URL, click around.
5. After that, every `git push` can redeploy automatically.

Don't reach for Kubernetes, custom domains, or CI/CD pipelines on day one. Get *something* live,
then improve it.
