#!/bin/bash
# bet: none (L4 — consent boundary on handing the person's private address to outside services)
# sunset: never (privacy)
# PreToolUse(Bash|WebFetch|WebSearch|Write|Edit|MultiEdit|NotebookEdit|mcp__*): ask the
# person before a tool call sends one of their private email addresses off the machine.
# Agents sign a scraper politely, a User-Agent or From header "with a contact address", and
# fill in the person's own address, which then sits in the logs of every site fetched.
#
# The addresses are DEV_HOOKS_PRIVATE_EMAILS (comma- or space-separated, in .claude settings
# "env"), else the global git user.email. A public alias meant for this stays off the list.
#
# What counts as sending, per tool (case-insensitive; an address also counts as %40):
#   Bash      — an address outside git's identity settings (user.email, GIT_*_EMAIL, a
#               git_email key, --author, commit trailers) in a command that reaches the network: curl,
#               wget, gh, an HTTP library, a URL. The whole command is judged, since the
#               address is often set in a variable that a later curl uses.
#   WebFetch  — the URL. WebSearch — the query. MCP tools — any argument.
#   Write, Edit, MultiEdit, NotebookEdit — a line that puts an address in a request: a
#               User-Agent, a From header, a contact string, a mailto=/email= parameter,
#               a headers map, a curl or wget call. Package metadata (spec.email) is silent.
#
# The ask carries the guard prefix, so the dev-hooks mod puts it to the person in a dialog
# rather than letting auto mode answer it.
#
# Opt out with DEV_HOOKS_EMAIL_GUARD=false in settings env.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

# COMMAND is the tool name, a newline, then the text that tool would send.
reminder_pre_init DEV_HOOKS_EMAIL_GUARD '.tool_name + "\n" + ((
  if .tool_name == "Bash" then .tool_input.command
  elif .tool_name == "WebFetch" then .tool_input.url
  elif .tool_name == "WebSearch" then .tool_input.query
  elif (.tool_name | test("^(Write|Edit|MultiEdit|NotebookEdit)$")) then
    [.tool_input.content, .tool_input.new_string, .tool_input.edits[]?.new_string,
      .tool_input.new_source] | map(select(type == "string")) | join("\n")
  elif (.tool_name | startswith("mcp__")) then .tool_input | tostring
  else "" end) // "")'
TOOL=${COMMAND%%$'\n'*}
TEXT=${COMMAND#*$'\n'}
case "$TEXT" in *@* | *%40*) ;; *) exit 0 ;; esac

LIST=${DEV_HOOKS_PRIVATE_EMAILS:-$(git config --global user.email 2>/dev/null)}
IFS=$', \t\n' read -r -d '' -a ADDRS <<<"$LIST"
[ "${#ADDRS[@]}" -gt 0 ] || exit 0

if [ "$TOOL" = Bash ]; then
  # Git's identity settings name the address on purpose; drop them before looking.
  TEXT=$(printf '%s' "$TEXT" | sed -E "s/(user\\.email|git_email|_EMAIL)[[:space:]=:]+[\"']?[^\"'[:space:]]+//g; s/(--author[= ]|[Cc]o-[Aa]uthored-[Bb]y:|[Ss]igned-[Oo]ff-[Bb]y:)[^<]*<[^>]*>//g")
fi

shopt -s nocasematch
FOUND=""
GREP_ARGS=()
for addr in "${ADDRS[@]}"; do
  GREP_ARGS+=(-e "$addr" -e "${addr/@/%40}")
  [ -z "$FOUND" ] && [[ "$TEXT" == *"$addr"* || "$TEXT" == *"${addr/@/%40}"* ]] && FOUND=$addr
done
[ -n "$FOUND" ] || exit 0

TAIL="Allow only if you asked for this. If a site needs a contact address, use a public alias instead of your own."
case "$TOOL" in
  Bash)
    NET_RE='https?://|(^|[^[:alnum:]_.-])(curl|wget|xh|http|https|httpie|aria2c|nc|ncat|socat|telnet|sendmail|mailx|swaks|gh|glab)([^[:alnum:]_.-]|$)|requests\.|httpx|urllib|aiohttp|http\.client|fetch\(|axios|Net::HTTP|Faraday|HTTParty|open-uri|URI\.open|URLSession'
    printf '%s' "$TEXT" | grep -Eiq "$NET_RE" || exit 0
    WHAT="This command sends your private address $FOUND over the network, where the receiving site keeps it in its logs."
    ;;
  Write | Edit | MultiEdit | NotebookEdit)
    LINE_RE="user.?agent|(^|[^[:alnum:]_])ua[[:space:]]*[:=]|from:|[\"']from[\"']|contact|mailto|[?&]email=|headers|curl|wget|requests\\.|httpx|urllib|fetch\\("
    printf '%s\n' "$TEXT" | grep -iF "${GREP_ARGS[@]}" | grep -Eiq "$LINE_RE" || exit 0
    WHAT="This edit writes your private address $FOUND into a request (a User-Agent, header or contact field), so every request that code makes will carry it."
    ;;
  WebFetch) WHAT="This fetch puts your private address $FOUND in the URL it requests." ;;
  WebSearch) WHAT="This search sends your private address $FOUND to the search provider." ;;
  mcp__*) WHAT="This call hands your private address $FOUND to the $TOOL service." ;;
  *) exit 0 ;;
esac

reminder_emit_decision ask "dev-hooks guard — please confirm: $WHAT $TAIL"
