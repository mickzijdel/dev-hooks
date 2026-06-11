#!/bin/bash
# PreToolUse(Bash): inspect the bash command Claude is about to run and gate the
# genuinely dangerous ones before they execute. Aimed at people new to the terminal,
# whose agents might otherwise run an irreversible command on their say-so.
#
# Two decisions (everything else is silent → the normal permission flow proceeds):
#   deny — catastrophic, irreversible system damage (wipe the disk/home, fork bomb,
#          format/overwrite a block device, chmod the root tree world-writable). Blocked
#          outright with an explanation.
#   ask  — risky but legitimate (rm -rf a path, git history/working-tree destruction,
#          force-push, committing on main/master, piping a downloaded script straight to
#          a shell, sudo). Surfaced to the human to confirm, with a plain-language reason.
#
# Detection is deliberately conservative — it gates a short list of well-known footguns,
# not "anything that writes". Safe commands (ls, git status, npm test, …) pass straight
# through. Advisory by design; opt out per repo/user with DEV_HOOKS_BASH_GUARD=false
# (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
# Sets INPUT, COMMAND, CWD, SESSION (or exits 0 on opt-out / no command).
reminder_pre_init DEV_HOOKS_BASH_GUARD

# Match a pattern (extended regex, case-insensitive) anywhere in the command. Works on
# multi-line commands — grep scans line by line, so a footgun on any line is caught.
cmd_has() { printf '%s' "$COMMAND" | grep -Eqi "$1"; }

# `rm` invoked with BOTH force and recursive (-rf / -fr / -r … -f / --force … --recursive).
# A leading space/dash guards against matching `-f`/`-r` inside an unrelated path argument.
rm_force_recursive() {
  cmd_has '(^|[;&|[:space:]])rm([[:space:]]|$)' || return 1
  cmd_has '(^|[[:space:]])-[[:alnum:]]*f' || cmd_has '(^|[[:space:]])--force' || return 1
  cmd_has '(^|[[:space:]])-[[:alnum:]]*r' || cmd_has '(^|[[:space:]])--recursive' || return 1
  return 0
}

# A catastrophic rm target: the filesystem root, the home dir, or "everything".
targets_root() {
  # shellcheck disable=SC2016  # the literal $HOME is a regex passed to grep, not a shell expansion
  cmd_has '(^|[[:space:]])(/|~|/\*|~/\*?|\$HOME|/\.\.?)([[:space:]]|$)' ||
    cmd_has '(^|[[:space:]])/\*([[:space:]]|$)'
}

# `git push` with a force flag (--force / --force-with-lease / -f / -vf / …).
force_push() {
  cmd_has 'git[[:space:]].*push' || return 1
  cmd_has '(^|[[:space:]])--force' && return 0
  cmd_has '(^|[[:space:]])-[[:alnum:]]*f([[:space:]]|$)' && return 0
  return 1
}

# ── deny: irreversible system damage ─────────────────────────────────────────────
DENY=""
if cmd_has 'rm[[:space:]].*--no-preserve-root'; then
  DENY="\`rm --no-preserve-root\` removes the protection that stops you from deleting the entire filesystem."
elif rm_force_recursive && targets_root; then
  DENY="This is a recursive, forced delete of the filesystem root or your home directory — it would wipe your machine and cannot be undone."
elif cmd_has ':\(\)[[:space:]]*\{[[:space:]]*:[[:space:]]*\|[[:space:]]*:'; then
  DENY="This is a fork bomb — it spawns processes until the machine locks up."
elif cmd_has '(^|[;&|[:space:]])mkfs(\.[[:alnum:]]+)?([[:space:]]|$)'; then
  DENY="\`mkfs\` formats a disk/partition, destroying everything on it."
elif cmd_has '(^|[;&|[:space:]])dd[[:space:]].*[[:space:]]of=/dev/(sd|nvme|disk|hd|mmcblk|vd)'; then
  DENY="This \`dd\` writes directly to a raw disk device, which destroys the data on it."
elif cmd_has '>[[:space:]]*/dev/(sd|nvme|disk|hd|mmcblk|vd)[a-z0-9]'; then
  DENY="This redirects output straight onto a raw disk device, corrupting the drive."
elif cmd_has 'chmod[[:space:]].*(-[[:alnum:]]*R|--recursive)[[:space:]].*[0-7]*777[[:space:]]+/([[:space:]]|$)'; then
  DENY="A recursive \`chmod 777 /\` makes the whole system world-writable and is effectively unrecoverable."
fi
[ -n "$DENY" ] && reminder_emit_decision deny "BLOCKED by dev-hooks guard: $DENY If you genuinely intend this, run it yourself outside the agent."

# ── ask: risky but legitimate — make the human confirm ───────────────────────────
ASK=""
if rm_force_recursive; then
  ASK="This force-deletes files/directories recursively (\`rm -rf\`). Deleted files don't go to a trash/recycle bin — they're gone. Confirm the path is what you mean."
elif cmd_has '(^|[;&|[:space:]])sudo([[:space:]]|$)'; then
  ASK="This runs with \`sudo\` (administrator rights), so it can change anything on the system. Read it before approving."
elif cmd_has '(curl|wget)[[:space:]].*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh'; then
  ASK="This pipes a script downloaded from the internet straight into a shell (\`curl … | sh\`). You're running code you haven't seen. Prefer downloading it first and reading it, or confirm you trust the source."
elif cmd_has 'git[[:space:]].*reset[[:space:]].*--hard'; then
  ASK="\`git reset --hard\` throws away all uncommitted changes in your working tree with no undo. Confirm you don't need them."
elif cmd_has 'git[[:space:]].*clean[[:space:]].*-[[:alnum:]]*f'; then
  ASK="\`git clean -f\` permanently deletes untracked files (anything not yet committed). Confirm none of them matter."
elif cmd_has 'git[[:space:]].*checkout[[:space:]].*(--[[:space:]].|\.([[:space:]]|$))' || cmd_has 'git[[:space:]].*restore[[:space:]].*(--[[:space:]])?\.([[:space:]]|$)'; then
  ASK="This discards your uncommitted edits (\`git checkout/restore .\`) with no undo. Confirm you mean to throw them away."
elif force_push; then
  ASK="This is a force-push — it can overwrite commits on the remote that you or others rely on. Confirm this is your own branch and you mean to rewrite its history."
fi

# Committing or pushing while sitting on the main/master branch — a classic beginner
# footgun (skip the branch lookup unless the command actually commits/pushes).
if [ -z "$ASK" ] && cmd_has 'git[[:space:]].*(commit|push)([[:space:]]|$)'; then
  branch=$(git -C "$CWD" branch --show-current 2>/dev/null)
  case "$branch" in
    main | master)
      verb="change"
      cmd_has 'git[[:space:]].*commit' && verb="commit on"
      cmd_has 'git[[:space:]].*push' && verb="push to"
      ASK="You're about to $verb the \`$branch\` branch directly. The safer habit is to make changes on a separate branch and open a pull request, so \`$branch\` always stays working. Confirm if you really want to change \`$branch\` directly."
      ;;
  esac
fi

[ -n "$ASK" ] && reminder_emit_decision ask "dev-hooks guard — please confirm: $ASK"

# Nothing matched → stay silent, let the normal permission flow handle it.
exit 0
