---
name: retro
description: Flag that this session went badly, with the user's note, for the weekly automation review to diagnose later. Runs only when the user types /retro.
disable-model-invocation: true
argument-hint: "[#tag ...] <what went wrong>"
---

# Retro

The user flagged this session as going badly. dev-hooks' prompt log has already recorded the
`/retro` line with its time, folder and session id, and the weekly automation review reads it
from there, then diagnoses the session from its transcript with fresh eyes. Write nothing and
don't diagnose now: the session that went wrong is the worst place to judge why.

1. If `$ARGUMENTS` is empty, ask for one line on what went wrong, and tell the user to send it as
   `/retro <note>` so the log records it.
2. If `~/.claude/automation-review/prompts.jsonl` doesn't exist, the prompt log is off and the
   note wasn't saved: say so, and that dev-hooks' prompt log is what records it.
3. Otherwise reply in one line that it's logged for the weekly review, then carry on with what you
   were doing. Change course only if the note itself asks you to.
