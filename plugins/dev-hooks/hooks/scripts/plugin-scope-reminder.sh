#!/bin/bash
# bet: none (L1 — a per-project plugin layout: plugins kept off globally, switched on where needed)
# sunset: never (preference)
# SessionStart / UserPromptSubmit: a plugin that's switched off for this project but whose
# trigger matches gets Claude to offer switching it on here (`claude plugin enable <id>
# --scope local`) and to ask the user for /reload-plugins. For plugins kept off globally to
# save context, so a repo or a request that needs one doesn't silently go without.
#
# Triggers live in ${XDG_CONFIG_HOME:-~/.config}/dev-hooks/plugin-triggers.json, keyed by
# plugin id: {"file": "<path in the project>", "match": "<grep -E pattern>"} is checked at
# SessionStart (without "match", the file existing is enough); {"prompt": "<grep -Ei
# pattern>"} is checked against the words the user typed, once per session per plugin.
# No file, no-op. "Switched off here" means the id's enabledPlugins value is false after
# Claude Code's own precedence: user < project .claude/settings.json < .claude/settings.local.json.
# Arg: session | prompt. Opt out with DEV_HOOKS_PLUGIN_TRIGGERS=false.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/dev-hooks/plugin-triggers.json"
[ -f "$CONF" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

MODE="${1:-session}"
if [ "$MODE" = prompt ]; then
  reminder_prompt_init DEV_HOOKS_PLUGIN_TRIGGERS
  reminder_prompt_typed
  TYPED=$REPLY
  [ -z "$TYPED" ] && exit 0
else
  reminder_opt_out DEV_HOOKS_PLUGIN_TRIGGERS
  reminder_session_init
fi

ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || ROOT=$CWD
SETTINGS=()
for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" \
  "$ROOT/.claude/settings.json" "$ROOT/.claude/settings.local.json"; do
  [ -f "$f" ] && SETTINGS+=("$f")
done
[ ${#SETTINGS[@]} -eq 0 ] && exit 0

# One row per configured plugin that's off here: id, file, match, prompt. Joined with the
# unit separator, not @tsv, which would double the backslashes in a pattern.
mapfile -t ROWS < <(jq -rn --slurpfile conf "$CONF" '
  (reduce inputs as $s ({}; . + ($s.enabledPlugins // {}))) as $on
  | $conf[0] | to_entries[] | select($on[.key] == false)
  | [.key, .value.file // "", .value.match // "", .value.prompt // ""] | join("\u001f")
' "${SETTINGS[@]}" 2>/dev/null)

HITS=""
for row in "${ROWS[@]}"; do
  IFS=$'\x1f' read -r id file match pattern <<<"$row"
  if [ "$MODE" = prompt ]; then
    [ -n "$pattern" ] || continue
    printf '%s' "$TYPED" | grep -Eiq -- "$pattern" || continue
    reminder_fire_once plugin-scope "$id" || continue
    HITS+="- \`$id\` (the user's message matches \`$pattern\`): \`claude plugin enable $id --scope local\`"$'\n'
  else
    [ -n "$file" ] && [ -f "$ROOT/$file" ] || continue
    [ -z "$match" ] || grep -Eq -- "$match" "$ROOT/$file" || continue
    HITS+="- \`$id\` (\`$file\` matches): \`claude plugin enable $id --scope local\`"$'\n'
  fi
done
[ -z "$HITS" ] && exit 0

MSG="These plugins are switched off for $ROOT but look needed here:
${HITS}Before relying on them, tell the user and offer to switch each one on for this project only by running its command in $ROOT (it writes the gitignored .claude/settings.local.json). Its skills, hooks and tools load once the user types /reload-plugins, so ask them to."

if [ "$MODE" = prompt ]; then
  reminder_emit_prompt "$MSG"
fi
reminder_emit_session "$MSG"
