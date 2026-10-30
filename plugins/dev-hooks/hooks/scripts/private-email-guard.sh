#!/bin/bash
# bet: none (L4 — consent boundary on handing an email address to outside services)
# sunset: never (privacy)
# PreToolUse(Bash|WebFetch|WebSearch|Write|Edit|MultiEdit|NotebookEdit|mcp__*): ask the
# person before a tool call sends an email address off the machine, unless it is on their
# allowlist. Agents sign a scraper politely, a User-Agent or From header "with a contact
# address", and fill in the person's own address, which then sits in the logs of every site
# fetched; other people's addresses leak the same way.
#
# Allowed addresses are DEV_HOOKS_ALLOWED_EMAILS (comma- or space-separated, in .claude
# settings "env"), such as a public alias for bots; with none set, every address asks.
# Reserved documentation and test domains (example.com/.org/.net, *.example, *.test,
# *.invalid, *.localhost) never count, and nor does an ssh or scp login (user@host:path).
#
# What counts as sending, per tool (case-insensitive; %40 counts as @):
#   Bash      — an address outside git's identity settings (user.email, GIT_*_EMAIL, a
#               git_email key, --author, commit trailers) in a command that reaches the
#               network: curl, wget, gh, an HTTP library, a URL. The whole command is judged,
#               since the address is often set in a variable that a later curl uses. A
#               command whose only targets are this machine (localhost, 127.0.0.1, 0.0.0.0,
#               [::1]) stays silent.
#   WebFetch  — the URL. WebSearch — the query. MCP tools — any argument.
#   Write, Edit, MultiEdit, NotebookEdit — a line that puts an address in a request: a
#               User-Agent, a From header, a contact string, a mailto=/email= parameter,
#               a headers map, a curl or wget call. Package metadata (spec.email) is silent.
#
# The ask carries the guard prefix, so the dev-hooks mod puts it to the person in a dialog
# rather than letting auto mode answer it. It names every address it asks about after
# "Not on your allowed list (DEV_HOOKS_ALLOWED_EMAILS): ", where the mod reads them to
# offer allowing them for the rest of the session (register.tsx EMAIL_ASK_MARK).
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

case "$TOOL" in
  Bash)
    # Git's identity settings name the address on purpose; drop them before looking.
    TEXT=$(printf '%s' "$TEXT" | sed -E "s/(user\\.email|git_email|_EMAIL)[[:space:]=:]+[\"']?[^\"'[:space:]]+//g; s/(--author[= ]|[Cc]o-[Aa]uthored-[Bb]y:|[Ss]igned-[Oo]ff-[Bb]y:)[^<]*<[^>]*>//g")
    NET_RE='https?://|(^|[^[:alnum:]_.-])(curl|wget|xh|http|https|httpie|aria2c|nc|ncat|socat|telnet|sendmail|mailx|swaks|gh|glab)([^[:alnum:]_.-]|$)|requests\.|httpx|urllib|aiohttp|http\.client|fetch\(|axios|Net::HTTP|Faraday|HTTParty|open-uri|URI\.open|URLSession'
    LOCAL_RE="(https?://)?(localhost|127\\.0\\.0\\.1|0\\.0\\.0\\.0|\\[::1\\])(:[0-9]+)?(/[^[:space:]\"']*)?"
    REMOTE=$(printf '%s' "$TEXT" | sed -E "s#$LOCAL_RE##g")
    # Out to the network: a URL that isn't this machine, or a network tool with no local target.
    if ! printf '%s' "$REMOTE" | grep -Eiq 'https?://'; then
      [ "$REMOTE" = "$TEXT" ] && printf '%s' "$TEXT" | grep -Eiq "$NET_RE" || exit 0
    fi
    ;;
  Write | Edit | MultiEdit | NotebookEdit)
    LINE_RE="user.?agent|(^|[^[:alnum:]_])ua[[:space:]]*[:=]|from:|[\"']from[\"']|contact|mailto|[?&]email=|headers|curl|wget|requests\\.|httpx|urllib|fetch\\("
    TEXT=$(printf '%s\n' "$TEXT" | grep -Ei "$LINE_RE")
    ;;
  WebFetch | WebSearch | mcp__*) ;;
  *) exit 0 ;;
esac

IFS=$', \t\n' read -r -d '' -a ALLOWED <<<"${DEV_HOOKS_ALLOWED_EMAILS:-}"
FOUND=()
while IFS= read -r addr; do
  case "$addr" in *:) continue ;; esac
  addr=${addr/\%40/@}
  addr=${addr,,}
  case "${addr#*@}" in
    example.com | example.org | example.net | *.example.com | *.example.org | *.example.net | *.example | *.test | *.invalid | *.localhost) continue ;;
  esac
  for ok in "${ALLOWED[@]}" "${FOUND[@]}"; do [ "$addr" = "${ok,,}" ] && continue 2; done
  FOUND+=("$addr")
done < <(printf '%s\n' "$TEXT" | grep -oiE '[[:alnum:]._%+-]+(@|%40)[[:alnum:]-]+(\.[[:alnum:]-]+)*\.[[:alpha:]]{2,}:?')
[ "${#FOUND[@]}" -gt 0 ] || exit 0
printf -v LIST '%s, ' "${FOUND[@]}"
ADDRESS="an email address"
[ "${#FOUND[@]}" -gt 1 ] && ADDRESS="email addresses"

case "$TOOL" in
  Bash) WHAT="This command sends $ADDRESS over the network, where the receiving site keeps a copy in its logs." ;;
  WebFetch) WHAT="This fetch puts $ADDRESS in the URL it requests." ;;
  WebSearch) WHAT="This search sends $ADDRESS to the search provider." ;;
  mcp__*) WHAT="This call hands $ADDRESS to the $TOOL service." ;;
  *) WHAT="This edit writes $ADDRESS into a request (a User-Agent, header or contact field), so every request that code makes will carry it." ;;
esac

reminder_emit_decision ask "dev-hooks guard — please confirm: $WHAT Not on your allowed list (DEV_HOOKS_ALLOWED_EMAILS): ${LIST%, }. Allow only if you asked for this; if a site needs a contact address, use an allowed one."
