#!/bin/bash
# bet: none (L4 — consent boundary on irreversible commands, not a capability gap)
# sunset: never (safety)
# PreToolUse(Bash): block the handful of bash commands that cause catastrophic,
# irreversible system damage before they execute. Aimed at people new to the terminal,
# whose agents might otherwise run a machine-wiping command on their say-so, in a mode
# where nothing else would catch it.
#
# Only the catastrophic few are gated — wipe the disk/home (rm -rf /), fork bomb,
# format a filesystem (mkfs), overwrite a raw block device (dd of=/dev/…), or make the
# whole root tree world-writable (chmod -R 777 /). Everything else — including risky
# but legitimate commands like `rm -rf some/path`, `git reset --hard`, force-push, or
# `curl … | sh` — passes straight through to the normal permission flow, which already
# prompts on them (and Claude Code's own auto-mode classifier catches them besides).
#
# The command is split into simple-command segments (newlines and the ;, &, | operators
# end one), and each command's flags and operands are judged only against that command —
# so `cd ~ && rm -rf build/` isn't read as `rm -rf ~`, and a commit message that merely
# *mentions* a footgun doesn't trip it.
#
# What happens on a match is configurable with DEV_HOOKS_GUARD_DENY (in .claude
# settings "env"):
#   unset / deny / 1 / true  — block outright (default; the command can't run)
#   ask                      — downgrade to a human confirmation instead of a block
#   allow / off / false / 0  — pass through silently (advanced users who rely on
#                              auto-mode or their own permission rules)
#
# Extra, opt-in check: committing/pushing while sitting on main/master asks for
# confirmation when DEV_HOOKS_GUARD_MAIN=1 (the coding-onboarding plugin's
# getting-started skill seeds this for beginners when installed; anyone can set it
# manually — solo main-branch workflows aren't nagged by default). No built-in replaces
# this workflow-habit nudge.
#
# Second check: commands whose *output* puts a secret value into the transcript —
# printing a secret-bearing file (`cat .env`, `cat config/master.key`), a secret
# manager read that prints to stdout (`bws secret get`, `op read`, `gh auth token`),
# or echoing a secret-named variable. Once a value is in the transcript it is logged,
# summarised, and pasted onward, and the only real remedy is rotating the credential.
# So this asks for a confirmation beat rather than blocking: every one of these is a
# command you legitimately need. Configurable with DEV_HOOKS_GUARD_SECRETS:
#   unset / ask              — confirm first (default)
#   deny                     — block outright
#   allow / off / false / 0  — pass through silently
# Deliberately narrow: template files (.env.example), public key halves (*.pub),
# inject-don't-print wrappers (`fnox run`, `bws run`, `op run`), `source .env`,
# counting greps, and output redirected to /dev/null all stay silent.
#
# Advisory by design; opt out of the whole hook per repo/user with
# DEV_HOOKS_BASH_GUARD=false (in .claude settings "env").

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
# `sudo rm …` is judged as `rm …`.
seg_parse() {
  local -a w
  read -ra w <<<"$1"
  NAME="" ARGS=()
  local i=0
  while [ "$i" -lt "${#w[@]}" ]; do
    case "${w[$i]##*/}" in
      sudo | command | nohup | time | env | xargs | *=*)
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

# The segment's non-flag operands, space-joined, so a secret-manager read can be
# recognised by its subcommand chain ("secret get", "kv get") regardless of flags.
seg_words() {
  WORDS=""
  local a
  for a in "${ARGS[@]}"; do
    case "$a" in -*) continue ;; esac
    unquote "$a"
    WORDS="$WORDS $UQ"
  done
  WORDS="${WORDS# } "
}

# Does this operand resolve to a file that actually exists? The segment parser
# word-splits without honouring quotes, so a quoted grep pattern arrives as several
# operands and one of them can look exactly like a key file (`event.key` from
# `grep 'event.key === "Escape"' src/x.ts`). Requiring the file to exist settles it,
# and costs no coverage: a path that isn't there can't be printed either.
file_exists() {
  local q=$1
  # shellcheck disable=SC2088,SC2016  # ~ / $HOME are literal *text* in the inspected command; expanding them is this function's job
  case "$q" in
    '~/'*) q="$HOME/${q#\~/}" ;;
    '$HOME/'*) q="$HOME/${q#\$HOME/}" ;;
    '${HOME}/'*) q="$HOME/${q#\$\{HOME\}/}" ;;
  esac
  case "$q" in
    /*) [ -f "$q" ] ;;
    *) [ -f "${SEG_CWD:-.}/$q" ] ;;
  esac
}

# `cd` in an earlier segment moves where a later relative path resolves, and Mick's
# commands routinely open with one (`cd repo && cat .env`). Track it so those reads
# are still recognised.
seg_cd() {
  local a
  for a in "${ARGS[@]}"; do
    case "$a" in -*) continue ;; esac
    unquote "$a"
    # shellcheck disable=SC2088,SC2016  # literal text from the inspected command
    case "$UQ" in
      '~' | '$HOME') SEG_CWD="$HOME" ;;
      '~/'*) SEG_CWD="$HOME/${UQ#\~/}" ;;
      /*) SEG_CWD="$UQ" ;;
      *) SEG_CWD="$SEG_CWD/$UQ" ;;
    esac
    return
  done
  SEG_CWD="$HOME" # bare `cd` goes home
}

# Does this path name a file whose *contents* are secret values? Judged on the
# basename as literal text, so an absolute, relative, or quoted path reads alike.
path_is_secret() {
  local base=${1##*/}
  # Templates and public key halves carry placeholders, not values.
  case "$base" in
    *.example | *.sample | *.template | *.dist | *.pub) return 1 ;;
  esac
  case "$base" in
    .env | .env.* | *.key | *.pem | *.p12 | *.pfx | *.jks | *.keystore | \
      id_rsa | id_dsa | id_ecdsa | id_ed25519 | \
      .netrc | .pgpass | .npmrc | .pypirc | \
      credentials | credentials.json | credentials.yml.enc | \
      client_secret*.json | service*account*.json | \
      secrets.json | secrets.yml | secrets.yaml) return 0 ;;
  esac
  return 1
}

# Is this operand a secret-shaped variable name? Matched on the name's own text, so
# $PATH and $HOME never qualify. `$` is required for echo/printf ($1 = "ref"), because
# a bare secret-shaped *word* is almost always a label reporting presence
# (`echo "BWS_ACCESS_TOKEN present"`) rather than the value; printenv takes the bare
# name as its argument, so there it is optional ($1 = "name").
is_secret_var() {
  local re='[A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|APIKEY|_KEY|KEY_)[A-Za-z0-9_]*'
  local anchored="^\\\$\\{?$re\\}?$"
  [ "$1" = name ] && anchored="^\\\$?\\{?$re\\}?$"
  printf '%s' "$2" | grep -Eq "$anchored"
}

# ── catastrophic, irreversible system damage ─────────────────────────────────────
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

# What to do on a catastrophic match — configurable for advanced users.
if [ -n "$DENY" ]; then
  case "${DEV_HOOKS_GUARD_DENY:-deny}" in
    ask | ASK | Ask)
      reminder_emit_decision ask "dev-hooks guard — please confirm: $DENY"
      ;;
    allow | ALLOW | off | OFF | false | FALSE | False | 0 | no | NO)
      : # advanced opt-out — fall through to the normal permission flow.
      ;;
    *)
      reminder_emit_decision deny "BLOCKED by dev-hooks guard: $DENY If you genuinely intend this, run it yourself outside the agent."
      ;;
  esac
fi

# ── secrets that would land in the transcript ────────────────────────────────────
SECRET_ASK=""
case "${DEV_HOOKS_GUARD_SECRETS:-ask}" in
  allow | ALLOW | off | OFF | false | FALSE | False | 0 | no | NO) ;;
  *)
    SEG_CWD="${CWD:-.}"
    while IFS= read -r seg; do
      # Output that goes nowhere can't reach the transcript.
      printf '%s' "$seg" | grep -Eq '>[[:space:]]*/dev/null' && continue
      seg_parse "$seg"
      [ -z "$NAME" ] && continue
      if [ "$NAME" = cd ]; then
        seg_cd
        continue
      fi
      case "$NAME" in
        cat | head | tail | less | more | bat | batcat | strings | xxd | od | jq | yq | grep | rg | ag)
          # A grep that reports whether, not what, prints no values.
          skip=""
          for a in "${ARGS[@]}"; do
            case "$a" in
              --count | --quiet | --silent | --files-with-matches | --files-without-match) skip=1 ;;
              --*) ;;
              -*[clLq]*) skip=1 ;;
            esac
          done
          [ -n "$skip" ] && continue
          for a in "${ARGS[@]}"; do
            case "$a" in -*) continue ;; esac
            unquote "$a"
            if path_is_secret "$UQ" && file_exists "$UQ"; then
              SECRET_ASK="\`$NAME $UQ\` prints the contents of a file that holds secret values."
              break
            fi
          done
          ;;
        bws | fnox | op | vault | gh | aws | doppler | kubectl | pass)
          seg_words
          case "$NAME:$WORDS" in
            bws:'secret get '* | bws:'secret list '* | \
              fnox:'get '* | fnox:'show '* | \
              op:'read '* | op:'item get '* | \
              vault:'kv get '* | vault:'read '* | \
              gh:'auth token '* | \
              aws:'secretsmanager get-secret-value '* | aws:'ssm get-parameter '* | \
              doppler:'secrets get '* | doppler:'secrets download '* | \
              kubectl:'get secret '* | kubectl:'get secrets '* | \
              pass:'show '*)
              SECRET_ASK="\`$NAME\` prints the secret's value to stdout."
              ;;
          esac
          ;;
        echo | printf | printenv)
          kind=ref
          [ "$NAME" = printenv ] && kind=name
          for a in "${ARGS[@]}"; do
            unquote "$a"
            if is_secret_var "$kind" "$UQ"; then
              SECRET_ASK="This prints the value of \`$UQ\`, a secret-shaped variable."
              break
            fi
          done
          ;;
      esac
      [ -n "$SECRET_ASK" ] && break
    done <<<"$SEGMENTS"
    ;;
esac

if [ -n "$SECRET_ASK" ]; then
  REASON="dev-hooks guard — $SECRET_ASK Anything printed here enters the transcript, where it is logged and summarised, and the only real fix is rotating the credential. Prefer a form that doesn't print the value (\`fnox run\`/\`bws run\` to inject it, \`--output\` to a gitignored file, or asking the user to check it themselves). Confirm if you do need to see it."
  case "${DEV_HOOKS_GUARD_SECRETS:-ask}" in
    deny | DENY | 1 | true | TRUE | True)
      reminder_emit_decision deny "BLOCKED: $REASON"
      ;;
    *)
      reminder_emit_decision ask "$REASON"
      ;;
  esac
fi

# ── opt-in: committing/pushing while sitting on the main/master branch ────────────
# A classic beginner footgun that no built-in replaces. Opt-in (DEV_HOOKS_GUARD_MAIN=1):
# the coding-onboarding plugin's getting-started skill seeds it for beginners;
# established main-branch workflows shouldn't be prompted on every commit.
case "${DEV_HOOKS_GUARD_MAIN:-}" in
  1 | true | TRUE | True)
    GIT_COMMITS="" GIT_PUSHES=""
    while IFS= read -r seg; do
      seg_parse "$seg"
      [ "$NAME" = git ] || continue
      seg_git_sub
      case "$GIT_SUB" in
        commit) GIT_COMMITS=1 ;;
        push) GIT_PUSHES=1 ;;
      esac
    done <<<"$SEGMENTS"
    if [ -n "$GIT_COMMITS" ] || [ -n "$GIT_PUSHES" ]; then
      branch=$(git -C "$CWD" branch --show-current 2>/dev/null)
      case "$branch" in
        main | master)
          verb="change"
          [ -n "$GIT_COMMITS" ] && verb="commit on"
          [ -n "$GIT_PUSHES" ] && verb="push to"
          reminder_emit_decision ask "dev-hooks guard — please confirm: You're about to $verb the \`$branch\` branch directly. The safer habit is to make changes on a separate branch and open a pull request, so \`$branch\` always stays working. Confirm if you really want to change \`$branch\` directly."
          ;;
      esac
    fi
    ;;
esac

# Nothing matched → stay silent, let the normal permission flow handle it.
exit 0
