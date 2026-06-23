#!/bin/bash
# PostToolUse(Write|Edit|MultiEdit): when Claude writes a database migration, nudge it toward
# safe-migration practice — reversibility, no data backfill mixed into a schema change, and
# lock-aware DDL (concurrent index creation, multi-step nullable→backfill→constraint). Rails
# wording first, with the Django/Alembic equivalents. Advisory only — emits additionalContext
# and always exits 0, never blocks the write.
#
# Fires for Rails (db/migrate/*.rb), Django (<app>/migrations/*.py), and Alembic
# (.../versions/*.py) migration files, at most once per session (marker under ${TMPDIR}).
#
# Opt out per repo/user with DEV_HOOKS_MIGRATION=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
# Sets INPUT, FILE, SESSION, TOOL, BASE (or exits 0 on opt-out / missing file_path).
reminder_init DEV_HOOKS_MIGRATION

# Migration framework's package __init__ is never a migration itself.
[ "$BASE" = "__init__.py" ] && exit 0

# Path gate: Rails db/migrate, Django app migrations/, Alembic|generic versions/.
case "$FILE" in
  */db/migrate/*.rb | db/migrate/*.rb) ;;
  */migrations/*.py | migrations/*.py) ;;
  */versions/*.py | versions/*.py) ;;
  *) exit 0 ;;
esac

# Fire at most once per session.
reminder_fire_once migration || exit 0

MSG="You just wrote a database migration ($BASE). Before finalizing, sanity-check it for safe-migration practice:
- Reversible: make sure it can roll back. In Rails prefer \`change\` (auto-reversible) or supply both \`up\`/\`down\`; use \`reversible\` for raw SQL. Django/Alembic: provide the reverse operation / \`downgrade()\`.
- No backfill in a schema migration: don't loop over rows or run a big UPDATE inside a structural migration — it locks the table and can't be batched. Do data changes in a separate, batched data migration (Rails: a maintenance task / separate migration; Django: a data migration with \`RunPython\`).
- Add columns safely: adding a NOT NULL column with a default, or a default to an existing column, can rewrite/lock the whole table on older engines. Prefer the multi-step path — add nullable, backfill in batches, then add the constraint.
- Index without locking: build large indexes concurrently. Rails: \`add_index ..., algorithm: :concurrently\` with \`disable_ddl_transaction!\`. Postgres: \`CREATE INDEX CONCURRENTLY\`. Django: \`AddIndexConcurrently\` (with \`atomic = False\`)."

reminder_emit "$MSG"
