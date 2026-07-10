#!/bin/bash
# bet: model won't pause on a huge uncommitted diff to suggest smaller commits / a review
# sunset: model proactively proposes splitting large changes
# Stop: when the session ends with a very large uncommitted change in the working tree,
# nudge Claude (exit 2) to slow down — commit in smaller pieces, get a review, and consider
# plan mode for the next chunk. Aimed at people new to coding, for whom a 2000-line
# uncommitted diff is hard to review and easy to lose. (It measures the whole tree, so
# pre-existing uncommitted work counts too — that diff is just as unreviewed.)
#
# Stays silent when a multi-session plan is already in progress (.claude/current_plan.md
# exists) — that means the work is already being driven deliberately. Fires at most once per
# session (transcript sentinel). Advisory only.
#
# Thresholds are tunable via env (defaults: 25 files OR 800 changed lines). Opt out per
# repo/user with DEV_HOOKS_BIG_CHANGE=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

reminder_opt_out DEV_HOOKS_BIG_CHANGE

SENTINEL="[big-change] large unreviewed change this session"
# Reads INPUT, resolves the transcript, and exits 0 if we've already prompted this session.
reminder_stop_init "$SENTINEL"

# Only meaningful inside a git repo.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Already working a deliberate, multi-session plan → don't second-guess the size.
[ -f .claude/current_plan.md ] && exit 0

reminder_changed_files # sets CHANGED (staged + unstaged + untracked filenames)
[ -z "$CHANGED" ] && exit 0

# Files: tracked changes from porcelain status + untracked files enumerated one by one
# (porcelain collapses an untracked directory into a single entry, hiding its contents).
tracked_files=$(git status --porcelain 2>/dev/null | grep -vc '^??')

# Added lines: additions across tracked files (numstat) + every line of untracked files.
tracked_added=$(git diff HEAD --numstat 2>/dev/null | awk '{ s += ($1 == "-" ? 0 : $1) } END { print s + 0 }')
untracked_files=0
untracked_added=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  untracked_files=$((untracked_files + 1))
  n=$(wc -l <"$f" 2>/dev/null || echo 0)
  untracked_added=$((untracked_added + n))
done < <(git ls-files --others --exclude-standard 2>/dev/null)
files=$((tracked_files + untracked_files))
lines=$((tracked_added + untracked_added))

FILES_THRESHOLD=${DEV_HOOKS_BIG_CHANGE_FILES:-25}
LINES_THRESHOLD=${DEV_HOOKS_BIG_CHANGE_LINES:-800}

if [ "$files" -lt "$FILES_THRESHOLD" ] && [ "$lines" -lt "$LINES_THRESHOLD" ]; then
  exit 0
fi

MSG="$SENTINEL: the working tree holds $files changed file(s) / ~$lines added lines and none of it is committed yet. A change this big is hard to review and easy to lose. Before finishing: commit the working pieces in small, focused commits (each with a clear message), make sure tests pass, and get a code review. For the next chunk, consider planning it first (plan mode) so the work stays in reviewable steps. If this size is expected for the task, say so and carry on."

reminder_emit_stop "$MSG"
