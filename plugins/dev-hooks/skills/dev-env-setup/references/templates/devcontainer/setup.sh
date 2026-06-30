#!/bin/sh
# postCreateCommand for the mise-driven devcontainer (dev-hooks:dev-env-setup standard).
# Order matters: chown the named volumes to the dev user, THEN mise trust -> mise install
# (provisions the toolchain from the bind-mounted mise.toml/mise.lock; runs the corepack
# postinstall hook if the project uses pnpm) -> hk install -> install project deps -> prepare DB.
set -e

# DB_*/MISE_DATA_DIR are injected by compose (environment:) and the Dockerfile (ENV); shellcheck
# can't see those assignments, so it would flag them as unassigned.
# shellcheck disable=SC2154

# Named volumes mount owned by root; hand them to the vscode user before use.
# KNOB — list the dependency-cache volume(s) you mounted in compose.yaml (e.g. /bundle, the
# node_modules / uv-cache / go-mod path) alongside the mise data dir.
echo "=== Fixing cache permissions ==="
sudo chown -R "$(whoami)" /bundle "$MISE_DATA_DIR"

# mise (mise.toml + mise.lock) owns the toolchain. Trust the bind-mounted config, then install
# the pinned runtime + dev tools. A from-source runtime compile (e.g. Ruby) runs once here and is
# cached on the mise-data volume for later rebuilds.
echo "=== Installing toolchain via mise ==="
mise trust --yes
# `mise install` also runs any [hooks] postinstall (e.g. `corepack enable`, see mise.toml), which
# makes the pnpm version pinned in package.json's `packageManager` field available via corepack —
# no `npm install -g pnpm`.
mise install

echo "=== Installing git hooks (hk) ==="
mise exec -- hk install

# KNOB — install the project's dependencies for your stack. The Ruby + pnpm example:
echo "=== Installing dependencies ==="
mise exec -- bundle install
mise exec -- pnpm install
# Python:  mise exec -- uv sync
# Node:    mise exec -- pnpm install   (or npm ci / yarn install)
# Go:      mise exec -- go mod download

# KNOB — accessory-service readiness + DB prepare. The MySQL example waits for the service, then
# imports a dump if present or sets up a fresh database. Drop this block if the project has no DB;
# swap the client/commands for postgres (pg_isready / bin/rails db:prepare), etc.
echo "=== Waiting for MySQL to be ready ==="
until mysql -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" --skip-ssl -e "SELECT 1" >/dev/null 2>&1; do
  echo "  MySQL not ready yet, retrying in 2s..."
  sleep 2
done
echo "  MySQL is ready."

if [ -f .devcontainer/dump.sql.gz ] && [ "$(zcat .devcontainer/dump.sql.gz | wc -c)" -gt 0 ]; then
  echo "=== Importing database dump ==="
  zcat .devcontainer/dump.sql.gz | mysql -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" --skip-ssl
  mise exec -- bin/rails db:migrate
  echo "  Import complete."
else
  echo "=== Preparing database ==="
  mise exec -- bin/rails db:prepare
fi

echo "=== Done! ==="
