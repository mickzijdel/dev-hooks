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
#          force-push, piping a downloaded script straight to a shell, sudo). Surfaced
#          to the human to confirm, with a plain-language reason.
#
# The command is split into simple-command segments (newlines and the ;, &, | operators
# end one), and each command's flags and operands are judged only against that command —
# so `cd ~ && rm -rf build/` isn't read as `rm -rf ~`, and a commit message that merely
# *mentions* a footgun doesn't trip it. Detection is deliberately conservative — a short
# list of well-known footguns, not "anything that writes". Safe commands (ls, git status,
# npm test, …) pass straight through.
#
# Extra, opt-in check: committing/pushing while sitting on main/master asks for
# confirmation when DEV_HOOKS_GUARD_MAIN=1 (the getting-started skill seeds this for
# beginners; solo main-branch workflows aren't nagged by default).
#
# Advisory by design; opt out per repo/user with DEV_HOOKS_BASH_GUARD=false
# (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
# Sets INPUT, COMMAND, CWD, SESSION (or exits 0 on opt-out / no command).
reminder_pre_init DEV_HOOKS_BASH_GUARD

# Match a pattern (extended regex, case-insensitive) anywhere in the raw command — only
# for the few footguns that inherently span command boundaries (a pipe, a redirect).
cmd_has() { printf '%s' "$COMMAND" | grep -Eqi "$1"; }

# Simple-command segments: newlines and the shell operators ;, &, | all end one (so &&
# and || do too). Splitting ignores quoting — a separator inside a quoted string only
# splits it into *more* segments, never glues two commands together.
SEGMENTS=$(printf '%s\n' "$COMMAND" | tr ';&|' '\n')

# Dissect one segment into NAME (the command word, any path prefix stripped) and ARGS.
# Wrappers (sudo, command, nohup, time, env, xargs) and env assignments are skipped so
# `sudo rm …` is judged as `rm …`; SUDO=1 records that sudo was involved.
seg_parse() {
  local -a w
  read -ra w <<<"$1"
  NAME="" ARGS=() SUDO=""
  local i=0
  while [ "$i" -lt "${#w[@]}" ]; do
    case "${w[$i]##*/}" in
      sudo)
        SUDO=1
        i=$((i + 1))
        ;;
      command | nohup | time | env | xargs | *=*)
        i=$((i + 1))
        ;;
      *) break ;;
    esac
  done
  [ "$i" -ge "${#w[@]}" ] && return
  NAME="${w[$i]##*/}"
  ARGS=("${w[@]:$((i + 1))}")
}

# Strip one layer of surrounding quotes from an operand (agents often quote paths).
unquote() {
  UQ=$1
  UQ=${UQ#\"}
  UQ=${UQ%\"}
  UQ=${UQ#\'}
  UQ=${UQ%\'}
}

# rm's own flags and operands: force, recursive, --no-preserve-root, and whether any
# operand is the filesystem root, the home dir, or "everything".
seg_rm() {
  RM_FORCE="" RM_RECUR="" RM_NOPRESERVE="" RM_ROOT=""
  local a
  for a in "${ARGS[@]}"; do
    unquote "$a"
    # shellcheck disable=SC2088,SC2016  # the ~ / $HOME patterns match literal *text* in the inspected command — expansion is exactly what we don't want
    case "$UQ" in
      --no-preserve-root) RM_NOPRESERVE=1 ;;
      --force) RM_FORCE=1 ;;
      --recursive) RM_RECUR=1 ;;
      --*) ;;
      -*)
        case "$UQ" in *f*) RM_FORCE=1 ;; esac
        case "$UQ" in *r* | *R*) RM_RECUR=1 ;; esac
        ;;
      '/' | '/*' | '~' | '~/' | '~/*' | '$HOME' | '$HOME/' | '$HOME/*' | '/.' | '/..') RM_ROOT=1 ;;
    esac
  done
}

# git's subcommand, skipping the global options that take a separate value.
seg_git_sub() {
  GIT_SUB=""
  local skip="" a
  for a in "${ARGS[@]}"; do
    if [ -n "$skip" ]; then
      skip=""
      continue
    fi
    case "$a" in
      -C | -c | --git-dir | --work-tree | --namespace) skip=1 ;;
      -*) ;;
      *)
        GIT_SUB="$a"
        return
        ;;
    esac
  done
}

# ── deny: irreversible system damage ─────────────────────────────────────────────
DENY=""
if cmd_has ':\(\)[[:space:]]*\{[[:space:]]*:[[:space:]]*\|[[:space:]]*:'; then
  DENY="This is a fork bomb — it spawns processes until the machine locks up."
elif cmd_has '>[[:space:]]*/dev/(sd|nvme|disk|hd|mmcblk|vd)[a-z0-9]'; then
  DENY="This redirects output straight onto a raw disk device, corrupting the drive."
fi

if [ -z "$DENY" ]; then
  while IFS= read -r seg; do
    seg_parse "$seg"
    [ -z "$NAME" ] && continue
    case "$NAME" in
      rm)
        seg_rm
        if [ -n "$RM_NOPRESERVE" ]; then
          DENY="\`rm --no-preserve-root\` removes the protection that stops you from deleting the entire filesystem."
        elif [ -n "$RM_FORCE" ] && [ -n "$RM_RECUR" ] && [ -n "$RM_ROOT" ]; then
          DENY="This is a recursive, forced delete of the filesystem root or your home directory — it would wipe your machine and cannot be undone."
        fi
        ;;
      mkfs | mkfs.*)
        DENY="\`mkfs\` formats a disk/partition, destroying everything on it."
        ;;
      dd)
        for a in "${ARGS[@]}"; do
          unquote "$a"
          case "$UQ" in
            of=/dev/sd* | of=/dev/nvme* | of=/dev/disk* | of=/dev/hd* | of=/dev/mmcblk* | of=/dev/vd*)
              DENY="This \`dd\` writes directly to a raw disk device, which destroys the data on it."
              ;;
          esac
        done
        ;;
      chmod)
        recur="" mode777="" on_root=""
        for a in "${ARGS[@]}"; do
          unquote "$a"
          case "$UQ" in
            --recursive) recur=1 ;;
            --*) ;;
            -*[rR]*) recur=1 ;;
            *777) mode777=1 ;;
            '/') on_root=1 ;;
          esac
        done
        if [ -n "$recur" ] && [ -n "$mode777" ] && [ -n "$on_root" ]; then
          DENY="A recursive \`chmod 777 /\` makes the whole system world-writable and is effectively unrecoverable."
        fi
        ;;
    esac
    [ -n "$DENY" ] && break
  done <<<"$SEGMENTS"
fi
[ -n "$DENY" ] && reminder_emit_decision deny "BLOCKED by dev-hooks guard: $DENY If you genuinely intend this, run it yourself outside the agent."

# ── ask: risky but legitimate — make the human confirm ───────────────────────────
ASK=""
GIT_COMMITS="" GIT_PUSHES=""
while IFS= read -r seg; do
  seg_parse "$seg"
  [ -z "$NAME" ] && continue
  case "$NAME" in
    rm)
      seg_rm
      if [ -n "$RM_FORCE" ] && [ -n "$RM_RECUR" ]; then
        ASK="This force-deletes files/directories recursively (\`rm -rf\`). Deleted files don't go to a trash/recycle bin — they're gone. Confirm the path is what you mean."
      fi
      ;;
    git)
      seg_git_sub
      case "$GIT_SUB" in
        commit) GIT_COMMITS=1 ;;
        push) GIT_PUSHES=1 ;;
      esac
      case "$GIT_SUB" in
        reset)
          for a in "${ARGS[@]}"; do
            [ "$a" = "--hard" ] && ASK="\`git reset --hard\` throws away all uncommitted changes in your working tree with no undo. Confirm you don't need them."
          done
          ;;
        clean)
          for a in "${ARGS[@]}"; do
            case "$a" in
              --force | -[!-]*f* | -f*) ASK="\`git clean -f\` permanently deletes untracked files (anything not yet committed). Confirm none of them matter." ;;
            esac
          done
          ;;
        checkout | restore)
          discard="" staged=""
          for a in "${ARGS[@]}"; do
            case "$a" in
              --staged) staged=1 ;;
              -- | .) discard=1 ;;
            esac
          done
          # `git restore --staged …` only unstages — nothing is lost.
          if [ "$GIT_SUB" = restore ] && [ -n "$staged" ]; then
            discard=""
          fi
          [ -n "$discard" ] && ASK="This discards your uncommitted edits (\`git checkout/restore\`) with no undo. Confirm you mean to throw them away."
          ;;
        push)
          for a in "${ARGS[@]}"; do
            case "$a" in
              --force | --force-with-lease* | --force-if-includes | -[!-]*f* | -f*)
                ASK="This is a force-push — it can overwrite commits on the remote that you or others rely on. Confirm this is your own branch and you mean to rewrite its history."
                ;;
            esac
          done
          ;;
      esac
      ;;
  esac
  if [ -z "$ASK" ] && [ -n "$SUDO" ]; then
    ASK="This runs with \`sudo\` (administrator rights), so it can change anything on the system. Read it before approving."
  fi
  [ -n "$ASK" ] && break
done <<<"$SEGMENTS"

if [ -z "$ASK" ] && cmd_has '(curl|wget)[[:space:]].*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh'; then
  ASK="This pipes a script downloaded from the internet straight into a shell (\`curl … | sh\`). You're running code you haven't seen. Prefer downloading it first and reading it, or confirm you trust the source."
fi

# Committing or pushing while sitting on the main/master branch — a classic beginner
# footgun. Opt-in (DEV_HOOKS_GUARD_MAIN=1): the getting-started skill seeds it for
# beginners; established main-branch workflows shouldn't be prompted on every commit.
if [ -z "$ASK" ] && { [ -n "$GIT_COMMITS" ] || [ -n "$GIT_PUSHES" ]; }; then
  case "${DEV_HOOKS_GUARD_MAIN:-}" in
    1 | true | TRUE | True)
      branch=$(git -C "$CWD" branch --show-current 2>/dev/null)
      case "$branch" in
        main | master)
          verb="change"
          [ -n "$GIT_COMMITS" ] && verb="commit on"
          [ -n "$GIT_PUSHES" ] && verb="push to"
          ASK="You're about to $verb the \`$branch\` branch directly. The safer habit is to make changes on a separate branch and open a pull request, so \`$branch\` always stays working. Confirm if you really want to change \`$branch\` directly."
          ;;
      esac
      ;;
  esac
fi

[ -n "$ASK" ] && reminder_emit_decision ask "dev-hooks guard — please confirm: $ASK"

# Nothing matched → stay silent, let the normal permission flow handle it.
exit 0
