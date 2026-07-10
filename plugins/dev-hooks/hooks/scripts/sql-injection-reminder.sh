#!/bin/bash
# bet: model interpolates values straight into SQL strings
# sunset: model reliably parameterizes queries / uses bind variables
# PostToolUse(Write|Edit|MultiEdit): when Claude writes a SQL statement with a value
# interpolated straight into the string — a Python f-string, Ruby "#{}" interpolation, or
# explicit string concatenation around SQL keywords — nudge it toward parameterized queries /
# ORM bind variables. Advisory only — emits additionalContext and always exits 0, never blocks.
#
# Scans only what this call ADDS (Write content + Edit/MultiEdit new_strings). Detection is
# conservative to limit noise: it requires a SQL keyword AND an interpolation marker in the
# same string. The %s / :name / ? styles are NOT flagged — those ARE the parameterized forms.
#
# Fires at most once per session (marker under ${TMPDIR}).
# Opt out per repo/user with DEV_HOOKS_SQL_INJECTION=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
# Sets INPUT, FILE, SESSION, TOOL, BASE (or exits 0 on opt-out / missing file_path).
reminder_init DEV_HOOKS_SQL_INJECTION

reminder_content # sets CONTENT (Write content + Edit/MultiEdit new_strings)
[ -z "$CONTENT" ] && exit 0

reminder_mktemp
CONTENT_FILE=$REPLY
printf '%s' "$CONTENT" >"$CONTENT_FILE"

FOUND=$(
  python3 - "$CONTENT_FILE" <<'PYEOF'
import re
import sys

with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    content = fh.read()

# A clause that strongly implies a real SQL statement (not just the word "select").
SQL = r"(?i)\b(?:SELECT\s+.+\s+FROM|INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM|WHERE\s+\w)"

# An interpolation marker in the same line as the SQL clause:
#  - Python f-string brace:     f"... {expr} ..."
#  - Ruby string interpolation: "... #{expr} ..."
#  - String concatenation:      "... " + var  /  var + " ..."
#  - .format()-built query
found = False
for line in content.splitlines():
    if not re.search(SQL, line):
        continue
    # f-string with a brace expression
    if re.search(r"(?i)\bf[\"'].*\{.+\}", line):
        found = True
        break
    # Ruby interpolation
    if re.search(r"#\{.+\}", line):
        found = True
        break
    # String concatenation of a SQL literal with a variable
    if re.search(r"[\"']\s*\+\s*[A-Za-z_]", line) or re.search(r"[A-Za-z_]\s*\+\s*[\"']", line):
        found = True
        break
    # .format(...) on the query string
    if re.search(r"[\"']\s*\.\s*format\s*\(", line):
        found = True
        break

print("1" if found else "")
PYEOF
)

[ -z "$FOUND" ] && exit 0

# Fire at most once per session.
reminder_fire_once sql_injection || exit 0

MSG="You just wrote SQL with a value interpolated directly into the query string in $BASE. That's the classic SQL-injection shape. Use parameterized queries / bind variables instead of building the string:
- Python (DB-API): cursor.execute(\"... WHERE id = %s\", (id,)) — pass params as the second arg, never an f-string.
- Rails/ActiveRecord: where(\"id = ?\", id) or where(id: id) — never \"id = #{id}\"; use sanitize_sql only as a last resort.
- Node: parameterized placeholders (\$1/?) with a values array, not template literals.
If the interpolated part is a trusted, validated identifier (e.g. a column name from an allowlist) rather than user data, this can be a false positive — ignore it."

reminder_emit "$MSG"
