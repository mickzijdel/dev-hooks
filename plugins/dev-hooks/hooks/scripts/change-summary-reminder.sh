#!/bin/bash
# Stop: when the session changed a meaningful number of files, nudge Claude to give (or
# finish giving, before it stops) a short, plain-language per-file account of what changed
# in each one — an aid for reviewing the session's work without having to re-read the raw
# diff, useful whether the person on the other end is a programmer or not. Complements
# review-reminder.sh (nudges toward *running a review*) and big-change-reminder.sh (nudges
# about *diff size*): neither produces a human-readable rundown of what happened per file.
#
# Fires at most once per session (its own sentinel string is the guard, checked via the
# transcript). Threshold is tunable via env (default: 3 changed files). Opt out per
# repo/user with DEV_HOOKS_CHANGE_SUMMARY=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

reminder_opt_out DEV_HOOKS_CHANGE_SUMMARY

SENTINEL="[change-summary] per-file change summary not yet given this session"
# Reads INPUT, resolves the transcript, and exits 0 if we've already prompted this session.
reminder_stop_init "$SENTINEL"

# Only meaningful inside a git repo.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

reminder_changed_files # sets CHANGED (staged + unstaged + untracked filenames)
[ -z "$CHANGED" ] && exit 0

files=$(echo "$CHANGED" | grep -c .)

FILES_THRESHOLD=${DEV_HOOKS_CHANGE_SUMMARY_FILES:-3}
[ "$files" -lt "$FILES_THRESHOLD" ] && exit 0

MSG="${SENTINEL}: this session changed $files file(s). Before finishing, give a short, plain-language summary of what changed in each file — one or two sentences per file, in everyday words rather than a diff dump, so it can be reviewed without reading the raw diff. Call out anything that looks unexpected or worth a second look. If you already gave this kind of per-file rundown earlier in the session, there's no need to repeat it."

reminder_emit_stop "$MSG"
