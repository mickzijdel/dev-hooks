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
| `WT_POST_SETUP="bin/rails db:prepare && …"` | shell command run inside the worktree after isolation, to create what the allocated names point at |

Values land in a generated, marker-delimited block in `mise.local.toml` (`[env]`), rewritten in
place on every run — never appended, never touching anything else in the file.

## Seeding the worktree (`WT_POST_SETUP`)

Isolation allocates *names* — a port, a database suffix. The databases behind those names do
not exist yet, and neither does a per-worktree asset build. That gap does not announce itself:
a test database that was never prepared throws `ActiveRecord::Deadlocked` in unrelated tests,
and a missing `public/vite-test` fails every JS-dependent system test at once. Both read as a
broken branch rather than a missing setup step, which is why documenting the commands in a
comment does not work — the person who needed them is the one who did not read them.

```sh
WT_POST_SETUP="bin/rails db:prepare && bin/rails db:test:prepare && RAILS_ENV=test bin/vite build"
```

It runs after isolation, from the worktree, through `mise x` so the commands see the generated
`mise.local.toml` (`PORT`, `WORKTREE_DB_SUFFIX`) rather than the ambient shell's values. A
worktree's mise env follows the *shell*, not the command's cwd, so this distinction is
load-bearing: seeding without it prepares the main checkout's database under the worktree's name.

Failure is reported (`post_setup=failed`, plus a line on stderr) but never fatal — a worktree
with unseeded databases is still a usable worktree, and aborting would strand it
half-provisioned. Cap a slow seed with `WT_POST_SETUP_TIMEOUT` (seconds, default 600).

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
