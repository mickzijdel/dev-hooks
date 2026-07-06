#!/bin/bash
# Stop hook: if this session's work added a noticeable number of code comments, remind
# Claude once to run the dev-hooks `compress-comments` skill before finishing, so
# comments that restate the code (narration, code-echo, planning forensics) get deleted
# and the rest compressed.
#
# Signal: added lines in `git diff HEAD` plus the full contents of untracked code files
# (an untracked file is all added lines), counted against a comment-start pattern.
# Shebangs and directive comments (shellcheck/eslint/noqa/...) don't count. Docstrings
# aren't counted either — the skill still reviews them; this hook only needs a cheap
# "wrote comments" signal, not full coverage. Fires at ≥3 comment lines so trivial
# sessions stay quiet, and at most once per session: the transcript guard matches
# "compress-comments", which both the sentinel below and any invocation of the skill
# itself contain — either means Claude was already told.
#
# Opt out with DEV_HOOKS_COMPRESS_COMMENTS=false in settings env.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

reminder_opt_out DEV_HOOKS_COMPRESS_COMMENTS

# ── Gate: must be a git repo with changed code files (mirrors review-reminder.sh) ──
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

reminder_changed_files # sets CHANGED
[ -z "$CHANGED" ] && exit 0
echo "$CHANGED" | grep -qE '\.(rb|erb|rake|py|js|ts|jsx|tsx|vue|mjs|cjs|sh)$' || exit 0

# Sets INPUT/TRANSCRIPT; exits 0 when the transcript already mentions the skill.
reminder_stop_init "compress-comments"

# ── Count comment lines this session added ──────────────────────────────────────
CODE_GLOBS=('*.rb' '*.erb' '*.rake' '*.py' '*.js' '*.ts' '*.jsx' '*.tsx' '*.vue' '*.mjs' '*.cjs' '*.sh')
# `*` needs trailing space/EOL: a bare `^\s*\*` would count Python's `*args,` lines.
COMMENT_RE='^[[:space:]]*(#|//|/\*|\*([[:space:]]|$))'
NOISE_RE='^[[:space:]]*#!|shellcheck|eslint|noqa|biome-ignore|jscpd:|rubocop:|type:[[:space:]]*ignore|frozen_string_literal'

COUNT=$(
  {
    git diff HEAD --no-color -- "${CODE_GLOBS[@]}" 2>/dev/null |
      grep -E '^\+' | grep -vE '^\+\+\+' | cut -c2-
    git ls-files -z --others --exclude-standard -- "${CODE_GLOBS[@]}" 2>/dev/null |
      xargs -0 -r cat 2>/dev/null
  } | grep -E "$COMMENT_RE" | grep -cvE "$NOISE_RE"
)
[ "${COUNT:-0}" -ge 3 ] || exit 0

# ── Emit the reminder ────────────────────────────────────────────────────────────
MSG="[compress-comments-reminder] This session added ${COUNT} comment lines. Before finishing, review the comments you wrote: run the dev-hooks compress-comments skill on this session's diff. Delete comments that restate the code (code-echo, change narration, planning forensics, reviewer justification); compress the rest. A comment survives only if it states something the code cannot show."

reminder_emit_stop "$MSG"
