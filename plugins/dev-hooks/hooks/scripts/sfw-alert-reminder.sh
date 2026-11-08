#!/bin/bash
# bet: none (L4 — a malware verdict on an install is Mick's call, not something to route round)
# sunset: never (safety)
# PostToolUse + PostToolUseFailure(Bash) hook: when a command's output carries a Socket Firewall
# (sfw) report that blocked a package, or flagged one with its AI scan, tell Claude to stop and
# report it to Mick instead of retrying or getting round the block. Advisory: sfw has already
# refused the fetch (or let a flagged one through); the hook only stops the next move.
#
# sfw runs inside the user's shell functions (`npm install` → `sfw npm install`), so the command
# text says nothing; the hook reads the result. A block exits 1, which Claude Code delivers as
# PostToolUseFailure with the text in `error`; a flagged install exits 0 (PostToolUse, text in
# tool_response stdout/stderr). Only sfw's own report counts: its `=== Socket Firewall ===`
# header on a line of its own, then a block line (free ` - blocked <registry> package: …`,
# enterprise `  BLOCKED: …`, or `failed to parse URL`, which also blocks) or the free tier's
# AI-scan warning and its ` - <id> - <url>` lines. A doc or search hit that quotes the wording
# without that layout stays silent.
#
# Opt out per repo/user with DEV_HOOKS_SFW_ALERT=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
reminder_post_bash_init DEV_HOOKS_SFW_ALERT

# Runs after every Bash call: a plain substring test before any jq.
case "$INPUT" in *'=== Socket Firewall ==='*) ;; *) exit 0 ;; esac

mapfile -t _ev < <(printf '%s' "$INPUT" | jq -r '.hook_event_name // "PostToolUse"' 2>/dev/null)
EVENT=${_ev[0]:-PostToolUse}

# B<TAB>line for a block, W<TAB>line for a flagged package; at most 10 of each.
FOUND=$(printf '%s' "$INPUT" | jq -r '
    [ (.tool_response | if type == "object" then (.stdout, .stderr) else . end), .error ]
    | map(select(type == "string")) | join("\n")' 2>/dev/null |
  sed -e 's/\x1b\[[0-9;]*[A-Za-z]//g' -e 's/\r$//' |
  awk '
    $0 == "=== Socket Firewall ===" { report = 1; warn = 0; next }
    !report { next }
    /^Potential malware detected with AI scan\. Not blocked by sfw-free:$/ { warn = 1; next }
    warn && /^ +- / { if (w++ < 10) print "W\t" substr($0, index($0, "- ") + 2); next }
    { warn = 0 }
    /^ - blocked [a-z]+ package: / || /^  BLOCKED( HOSTNAME)?: / || /failed to parse URL: / {
      line = $0; sub(/^ +(- )?/, "", line); if (b++ < 10) print "B\t" line
    }')
[ -n "$FOUND" ] || exit 0

reminder_cwd_session

BLOCKED=$(printf '%s\n' "$FOUND" | sed -n 's/^B\t/  - /p')
FLAGGED=$(printf '%s\n' "$FOUND" | sed -n 's/^W\t/  - /p')

MSG=""
if [ -n "$BLOCKED" ]; then
  MSG+="Socket Firewall blocked a package fetch in that command (Socket lists it as malware, or could not check it):"$'\n'"$BLOCKED"$'\n'"Stop here. Do not retry it, and do not get round the block: no \`command npm\` (or \`command uv\`, \`command pip\`, …), no other registry, mirror, package manager or version, no unset proxy or CA variables. "
fi
if [ -n "$FLAGGED" ]; then
  [ -n "$MSG" ] && MSG+=$'\n\n'
  MSG+="Socket Firewall's AI scan flagged a package in that command as potential malware. The free tier does not block it, so it may already be installed and its install scripts may have run:"$'\n'"$FLAGGED"$'\n'"Stop here. Do not run, import, build or test anything that loads it, and do not retry or get round the warning. "
fi
MSG+="Tell Mick which command fetched it, each package and version, and sfw's reason or link above (and, if you can see it without installing anything, which dependency pulled it in), then wait for his decision. If this was old sfw output you only printed (a log or a doc), not a fetch you just ran, say so and carry on."

reminder_emit "$MSG" "$EVENT"
