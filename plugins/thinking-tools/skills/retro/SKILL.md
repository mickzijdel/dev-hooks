---
name: retro
description: Log that this session went badly, with the user's note, for the weekly automation review to diagnose later. Runs only when the user types /retro.
disable-model-invocation: true
argument-hint: "[#tag ...] <what went wrong>"
---

# Retro

Save a one-line record that this session went badly, so the weekly automation review can
diagnose it later with fresh eyes and the whole transcript. Don't diagnose now: the session that
went wrong is the worst place to judge why.

1. Take the note from `$ARGUMENTS` exactly as typed, `#tags` included. If it's empty, ask for
   one line on what went wrong and wait.
2. Append it with this command, the note verbatim between the `NOTE` lines:

   ```bash
   mkdir -p ~/.claude/automation-review && jq -nc \
     --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg session "${CLAUDE_SESSION_ID}" --arg cwd "$PWD" \
     --rawfile note /dev/stdin '{ts: $ts, session: $session, cwd: $cwd, note: ($note | rtrimstr("\n"))}' \
     >>~/.claude/automation-review/retros.jsonl <<'NOTE'
   <the note>
   NOTE
   ```

3. Reply in one line that it's logged for the weekly review, then carry on with what you were
   doing. Change course only if the note itself asks you to.
