---
name: dockerfile
description: Use when writing or editing a Dockerfile/Containerfile (or any container image build) — covers cache-friendly layer ordering and common gotchas.
---

# Dockerfile

Use this skill to write Dockerfiles that rebuild fast and produce small, secure images.

## Core principle: order layers least → most frequently changed

Each instruction is a cached layer. Docker reuses a layer only if it **and every layer
above it** is unchanged. So put the things that rarely change at the top and the things
that change on every commit (your source code) last. The usual order:

1. `FROM` base image (pinned)
2. System packages (`apt-get`/`apk`)
3. Dependency manifests only — `COPY package.json package-lock.json ./` (or `Gemfile`,
   `requirements.txt`, `go.mod`)
4. `RUN` install dependencies
5. **Then** `COPY . .` — the app source
6. Build step, then `CMD`/`ENTRYPOINT`

This way editing source only invalidates the cache from step 5 down; the expensive
dependency install in step 4 stays cached.

## Before / after

```dockerfile
# ❌ Cache-busting: any source edit re-runs npm install
FROM node:22-slim
WORKDIR /app
COPY . .
RUN npm ci
CMD ["node", "server.js"]
```

```dockerfile
# ✅ Cache-friendly: npm ci is reused until package*.json changes
FROM node:22-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
CMD ["node", "server.js"]
```

## Gotchas

| Do | Why |
|----|-----|
| Pin the base image (`node:22.3-slim` or a `@sha256:` digest), never `latest` | Reproducible builds; `latest` silently drifts |
| Use multi-stage builds (`FROM … AS build` → copy artifacts into a slim final stage) | Keeps compilers/dev deps out of the shipped image |
| Add a `.dockerignore` (`.git`, `node_modules`, build output, secrets) | Smaller context + keeps `COPY . .` cache-stable |
| Combine `RUN` + clean caches in one layer: `apt-get update && apt-get install -y --no-install-recommends X && rm -rf /var/lib/apt/lists/*` | A separate `rm` in a later layer doesn't shrink the image |
| Prefer `COPY` over `ADD` (use `ADD` only for remote URLs / auto-extract) | `ADD` has surprising implicit behavior |
| Don't `apt-get upgrade` / `dist-upgrade` | Non-reproducible; update the base image instead |
| Create and switch to a non-root `USER` | Least privilege |
| Use exec form: `CMD ["node", "server.js"]` not `CMD node server.js` | Proper signal handling (SIGTERM) |
| Consider BuildKit cache mounts: `RUN --mount=type=cache,target=/root/.npm npm ci` | Reuses the package cache across builds |
| Never `chown -R` / `chmod -R` a directory holding a large dependency tree (`.venv`, `node_modules`, site-packages) | `chown -R /app` rewrites **every** file into a new layer, so the whole dep tree is stored twice in the image — doubling push and registry-cache time. Set ownership as files land with `COPY --chown` (incl. `COPY --from=… --chown`), or only `chown` the small dirs that need write access |

## Don't `chown -R` a dependency tree

A recursive `chown`/`chmod` over a directory that contains a big install (a Python
`.venv`, `node_modules`, site-packages) rewrites every file, so Docker writes the
**entire tree into a fresh layer** — the dependencies end up stored twice in the image,
which doubles both the image push and any registry build-cache export. Set ownership
when the files are copied instead.

```dockerfile
# ❌ chown -R rewrites the whole venv into a second layer (torch shipped twice)
RUN useradd -m -u 1000 app
COPY --from=builder /app/.venv /app/.venv
COPY . .
RUN chown -R app:app /app          # duplicates .venv → ~2× push + cache time
USER app
```

```dockerfile
# ✅ ownership set as files land — the venv is stored once
RUN useradd -m -u 1000 app
COPY --from=builder --chown=app:app /app/.venv /app/.venv
COPY --chown=app:app . .
RUN mkdir -p /app/data && chown app:app /app/data   # only the dir that needs writes
USER app
```

## Lint

Run [hadolint](https://github.com/hadolint/hadolint), the standard Dockerfile linter:

```bash
hadolint Dockerfile
```

It catches unpinned versions, missing `--no-install-recommends`, `ADD` misuse, and more.
hadolint can't judge the things above — cache-friendly **ordering** and multi-stage
**strategy** — so apply this skill for those, and hadolint for the mechanical checks.

> In this plugin, the `dockerfile-reminder` hook runs `hadolint` automatically whenever you
> write a Dockerfile and reports the findings back — so you'll usually see results without
> running it yourself. Act on them.
