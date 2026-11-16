#!/bin/bash
# bet: model writes unsafe migrations (irreversible / locking / backfill-mixed)
# sunset: model reliably writes reversible, lock-aware, backfill-separated migrations
# PostToolUse(Write|Edit|MultiEdit): when Claude writes a database migration, nudge it toward
# safe-migration practice — reversibility, no data backfill mixed into a schema change, and
# lock-aware DDL (concurrent index creation, multi-step nullable→backfill→constraint). Rails
# wording first, with the Django/Alembic equivalents. Advisory only — emits additionalContext
# and always exits 0, never blocks the write.
#
# Fires for Rails (db/migrate/*.rb), Django (<app>/migrations/*.py), and Alembic
# (.../versions/*.py) migration files, at most once per session.
#
# UserPromptSubmit, `prompt` argument: the same rules when the typed prompt asks for a schema
# change. Own once-per-session marker, so the after-write check stays armed.
#
# Opt out per repo/user with DEV_HOOKS_MIGRATION=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

RULES="- Reversible: make sure it can roll back. In Rails prefer \`change\` (auto-reversible) or supply both \`up\`/\`down\`; use \`reversible\` for raw SQL. Django/Alembic: provide the reverse operation / \`downgrade()\`.
- No backfill in a schema migration: don't loop over rows or run a big UPDATE inside a structural migration — it locks the table and can't be batched. Do data changes in a separate, batched data migration (Rails: a maintenance task / separate migration; Django: a data migration with \`RunPython\`).
- Add columns safely: adding a NOT NULL column with a default, or a default to an existing column, can rewrite/lock the whole table on older engines. Prefer the multi-step path — add nullable, backfill in batches, then add the constraint.
- Index without locking: build large indexes concurrently. Rails: \`add_index ..., algorithm: :concurrently\` with \`disable_ddl_transaction!\`. Postgres: \`CREATE INDEX CONCURRENTLY\`. Django: \`AddIndexConcurrently\` (with \`atomic = False\`)."

if [ "${1:-}" = prompt ]; then
  reminder_prompt_init DEV_HOOKS_MIGRATION
  reminder_prompt_typed
  [ -n "$REPLY" ] || exit 0
  p="${REPLY,,}"

  # Misses are free: the Write check still fires. So every cue needs a database word.
  b='(^|[^a-z_])' e='([^a-z_]|$)' s='[[:blank:]]+'
  gap="([[:blank:],]+[a-z0-9_/&'\"\`:.()-]+){0,6}[[:blank:],]+"
  dbword="${b}(columns?|tables?|index(es)?|database|db|prisma|sql|rows?|records?|fields?|null)$e"
  hit=""
  # SQL wording has no everyday meaning.
  [[ $p =~ ${b}(alter${s}table|(create|drop)${s}table|drop${s}column|index(es)?${s}(on|concurrently)|foreign${s}keys?|(unique|not[[:blank:]-]null|check)${s}constraint)$e ]] && hit=1
  # Bare "migration" is often a project name.
  [[ $p =~ ${b}(db|database|rails|django|alembic|prisma|sql)[[:blank:]-]migrations?$e ]] && hit=1
  [[ $p =~ ${b}migrat(e|ing)${s}((the|our|this)${s})?(db|database|schema)$e ]] && hit=1
  if [[ $p =~ ${b}(migrations?|backfill[a-z]*)$e ]] && [[ $p =~ $dbword ]]; then hit=1; fi
  # "JSON schema" and "zod schema" are not database schemas.
  if [[ $p =~ ${b}schema${s}(changes?|migrations?)$e ]] &&
    ! [[ $p =~ ${b}(json|zod|graphql|openapi|yaml|xml)$e ]]; then hit=1; fi
  if [ -z "$hit" ]; then
    verb='(add|drop|remov|renam|delet|chang|alter|mak|creat)[a-z]{0,4}'
    tverb='(drop|remov|renam|delet|creat)[a-z]{0,4}'
    [[ $p =~ ${b}${verb}${gap}columns?$e ]] || [[ $p =~ ${b}${tverb}${gap}tables?$e ]] || exit 0
    # A column or table in a document, a spreadsheet or a UI.
    [[ $p =~ ${b}(readme|docs?|markdown|kanban|boards?|spreadsheets?|sheets?|airtable|css|html|grid|layout|components?|headers?|pages?|slides?|table${s}of${s}contents|ui|react|views?|nav|sidebar)$e ]] && exit 0
  fi

  reminder_fire_once migration_prompt || exit 0
  reminder_emit_prompt "This request looks like a database migration or schema change. Settle the approach before you write code, and state it in your opening lines:
$RULES
If the change is hard to undo (it drops data, or rewrites or locks a large table), ask the person about the approach now, not after the migration exists."
fi

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
$RULES"

reminder_emit "$MSG"
