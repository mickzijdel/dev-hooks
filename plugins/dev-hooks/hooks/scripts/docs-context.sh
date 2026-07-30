#!/bin/bash
# bet: model won't locate the project's docs/ before it needs them
# sunset: model reliably finds and consults project docs on its own
# SessionStart hook: if this project has a docs/ or doc/ directory containing
# Markdown files, emit a brief index (titles + optional descriptions from YAML
# frontmatter) so Claude knows where documentation lives and can consult the
# right files when working on related features. If a doc's frontmatter carries
# an opt-in `stale_after: YYYY-MM-DD` (past) or `status: stale|deprecated|draft`,
# its index line is flagged so Claude doesn't blindly trust an out-of-date doc.
# Neither field is required — docs without them render exactly as before.
# Advisory only — never blocks. Opt out: DEV_HOOKS_DOCS_CONTEXT=false.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
reminder_opt_out DEV_HOOKS_DOCS_CONTEXT

INPUT=$(cat 2>/dev/null)
DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$DIR" ] && DIR="$PWD"

# Locate a docs directory at the project root
DOCS_DIR=""
for candidate in "$DIR/docs" "$DIR/doc"; do
  if [ -d "$candidate" ]; then
    DOCS_DIR="$candidate"
    break
  fi
done
[ -z "$DOCS_DIR" ] && exit 0

# Collect .md files up to depth 2; skip hidden paths
mapfile -t MD_FILES < <(find "$DOCS_DIR" -maxdepth 2 -name "*.md" -not -path "*/.*" 2>/dev/null | sort)
[ "${#MD_FILES[@]}" -eq 0 ] && exit 0

MAX_FILES=30
TOTAL=${#MD_FILES[@]}
LINES=""
COUNT=0
TODAY=$(date +%Y-%m-%d 2>/dev/null)
for f in "${MD_FILES[@]}"; do
  [ "$COUNT" -ge "$MAX_FILES" ] && break
  REL="${f#"$DIR/"}"
  # Parse YAML frontmatter for title + description, falling back to first # heading.
  # stale_after/status are opt-in staleness metadata (see header comment) — absent for
  # most docs, in which case FLAG below stays empty and the line is unchanged.
  mapfile -t _meta < <(awk '
    /^---/{c++; if(c>1){exit}}
    c==1 && /^title:/{sub(/^title:[[:space:]]*/,""); gsub(/"/,""); _t=$0; next}
    c==1 && /^description:/{sub(/^description:[[:space:]]*/,""); gsub(/"/,""); _d=$0; next}
    c==1 && /^stale_after:/{sub(/^stale_after:[[:space:]]*/,""); gsub(/"/,""); _s=$0; next}
    c==1 && /^status:/{sub(/^status:[[:space:]]*/,""); gsub(/"/,""); _u=$0; next}
    c==0 && _t=="" && /^#[^#]/{sub(/^#+[[:space:]]*/,""); _t=$0}
    END{print _t; print _d; print _s; print _u}
  ' "$f" 2>/dev/null)
  TITLE="${_meta[0]:-}"
  DESC="${_meta[1]:-}"
  STALE_AFTER="${_meta[2]:-}"
  STATUS="${_meta[3]:-}"
  if [ -z "$TITLE" ]; then
    TITLE="${f##*/}"
    TITLE="${TITLE%.md}"
  fi
  FLAG=""
  case "$STATUS" in
    stale | deprecated | draft) FLAG=" ⚠ status: ${STATUS}" ;;
  esac
  if [ -z "$FLAG" ] && [[ "$STALE_AFTER" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [ -n "$TODAY" ]; then
    # ISO dates compare correctly as plain strings.
    [[ "$STALE_AFTER" < "$TODAY" ]] && FLAG=" ⚠ stale since ${STALE_AFTER}"
  fi
  if [ -n "$DESC" ]; then
    LINES="${LINES}  - ${REL}: ${TITLE} — ${DESC}${FLAG}\n"
  else
    LINES="${LINES}  - ${REL}: ${TITLE}${FLAG}\n"
  fi
  COUNT=$((COUNT + 1))
done
[ -z "$LINES" ] && exit 0

if [ "$TOTAL" -gt "$MAX_FILES" ]; then
  REMAINING=$((TOTAL - MAX_FILES))
  LINES="${LINES}  (${REMAINING} more files not shown — run \`find ${DOCS_DIR#"$DIR/"} -name '*.md'\` to see all)\n"
fi

LABEL="${DOCS_DIR#"$DIR/"}"
MSG="Project documentation found in ${LABEL}/:
$(printf '%b' "$LINES")
Consult these files when working on related features."

jq -cn --arg msg "$MSG" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $msg}}'
exit 0
