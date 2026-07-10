# Per-worktree isolation — full recipe

`isolate-worktree.sh` gives each worktree its own server + database so parallel worktrees don't
collide. It is opt-in: with no `.worktree-isolate.conf` at the repo root it is a no-op. This file
is the detail behind the summary in [SKILL.md](../SKILL.md#per-worktree-isolation).

## How the offset is allocated

Each worktree gets a small integer **offset** from which every isolated value derives. The
allocator:

- Keys off a **slug** — the sanitized branch name (`feat/x` → `feat_x`), falling back to the
  worktree's directory basename when detached.
- Stores `slug → offset` in a registry at `$(git rev-parse --git-common-dir)/worktree-ports.tsv`.
  The git *common* dir is shared by every worktree of the repo and is never committed.
- **Reuses** a slug's offset on re-run (stable ports across restarts), and **prunes** entries
  whose worktree no longer exists — so removing a worktree frees its offset for the next one.
- Reserves **offset 0** for the un-provisioned main checkout (still on the base port); worktrees
  start at offset 1.

## Config keys (`.worktree-isolate.conf`)

Committed, parsed as `KEY=VALUE` (inline `#` comments allowed). All keys optional — set only what
the project needs.

| Key | Effect |
|---|---|
| `WT_BASE_PORT=3000` | `PORT = base + offset` |
| `WT_EXTRA_PORTS="VITE_PORT=3036 …"` | space-separated `NAME=base` pairs; each gets `base + offset` |
| `WT_DB_SUFFIX_VAR=WORKTREE_DB_SUFFIX` | export `"_<slug>"` under this name for the app to append to its DB name |
| `WT_REDIS_URL_VAR=REDIS_URL` | `redis://localhost:6379/<offset>` (a distinct Redis logical DB per worktree) |
| `WT_COMPOSE_NAME=myapp` | emit `COMPOSE_PROJECT_NAME=<name>_<slug>` |
| `WT_COMPOSE_ENV=.devcontainer/.env` | also write `COMPOSE_PROJECT_NAME` + `PORT` into this compose-adjacent `.env` |

Values land in a generated, marker-delimited block in `mise.local.toml` (`[env]`), rewritten in
place on every run — never appended, never touching anything else in the file.

## Rails (host-native)

Read the exported suffix in `config/database.yml` so the DB name varies per worktree while the
main checkout stays on the plain name:

```yaml
development:
  <<: *default
  database: myapp_development<%= ENV.fetch("WORKTREE_DB_SUFFIX", "") %>
```

Then, in the worktree:

```bash
bin/rails db:prepare   # creates + migrates myapp_development_<slug> on first boot
bin/rails s            # binds $PORT (from mise.local.toml) — no collision with other worktrees
```

`bin/dev` / `Procfile.dev` honor `$PORT` too. `overmind`/`foreman` sockets live inside the
worktree dir, so they don't collide across worktrees.

## Devcontainer (per worktree)

A devcontainer-per-worktree gets DB + service isolation **for free**: the Dev Containers tooling
derives a distinct compose project from each workspace folder, so `.worktrees/feat-x` and
`.worktrees/feat-y` spin up separate Postgres containers, volumes, and networks. The suffix var
is then a harmless no-op inside the container.

Two things still want the offset:

- **Host-published port** — two running containers must not both publish the same host port. Set
  `WT_COMPOSE_ENV=.devcontainer/.env` so isolate writes the worktree's `PORT` there, and let the
  compose file publish it: `ports: - "${PORT:-3000}:${PORT:-3000}"` (docker compose reads
  `.devcontainer/.env` automatically). The [[dev-env-setup]] devcontainer template does exactly
  this as of its v21 standard; older templates hardcode `3000:3000` and need the one-line change.
- **`COMPOSE_PROJECT_NAME`** — also written to `WT_COMPOSE_ENV` for CLI-driven `docker compose`
  outside VS Code. VS Code's folder-derived project name already separates worktrees, so this is
  belt-and-suspenders.

## dotenv projects (alternative to mise)

If the app loads a dotenv file rather than mise env, point it at `mise.local.toml`'s values by
generating the same keys into `.env.local` (which `dotenv-rails` loads ahead of `.env`). The
overlay principle is identical: a generated block, never mutating the real `.env`.
