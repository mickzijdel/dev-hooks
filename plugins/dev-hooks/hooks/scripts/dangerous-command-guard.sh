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
# The command is split into the simple commands the shell would run (lib/shell-segments.awk
# honours quoting, and splits out $(…), backticks, `bash -c '…'`, `eval`, a heredoc fed
# to a shell, and what `ssh`, `docker`/`kubectl`/`incus exec`, `watch` and `script -c`
# run), and each command's flags and operands are judged only against that
# command — so `cd ~ && rm -rf build/` isn't read as `rm -rf ~`, and a commit message or
# search pattern that merely *mentions* a footgun doesn't trip it.
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
# manager read that prints to stdout (`bws secret get`, `op read`), a credential probe
# (`git credential fill`, a git or docker helper's `get`, `gh auth token`, `glab auth
# status -t`, `az account get-access-token`, `gcloud auth print-access-token`,
# `secret-tool lookup`), or
# echoing a secret-named variable. Once a value is in the transcript it is logged,
# summarised, and pasted onward, and the only real remedy is rotating the credential.
# So this BLOCKS rather than asking: `ask` selects whoever answers prompts, and under
# `"defaultMode": "auto"` that is the auto-mode classifier, which reads a two-branch
# `${VAR:+SET}${VAR:-UNSET}` as the presence check it is dressed up as. Deny is right
# because the act is irreversible AND a non-printing form always exists.
# Configurable with DEV_HOOKS_GUARD_SECRETS:
#   unset / deny             — block outright (default)
#   ask                      — confirm first; only a safeguard if a human answers
#   allow / off / false / 0  — pass through silently
# Deliberately narrow: template files (.env.example), public key halves (*.pub),
# inject-don't-print wrappers (`fnox run`, `bws run`, `op run`), `source .env`,
# counting greps, and stdout sent to /dev/null or a file or captured into a variable
# (`v=$(fnox get X)`) all stay silent; `2>/dev/null` hides only stderr, so it does not.
# So do the two parameter expansions that cannot print a value — `${VAR:+word}` and
# `${#VAR}` — since those are the forms to reach for; `${VAR:-word}` is *not* one of
# them and is caught.
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

# Simple-command segments, split the way the shell would by lib/shell-segments.awk: one
# per line, words separated by \037 with their quotes removed, wrappers (sudo, env,
# xargs, …) and leading assignments already dropped, and each redirection as one word
# starting with \035. Quoting decides what is code, so a separator inside a quoted
# string (`rg "fnox get|bws secret get"`, a commit message) no longer starts a command,
# while $(…), backticks, `bash -c '…'`, `eval`, `ssh host …`, a heredoc fed to a
# shell and a runner's command (`docker exec c …`, `watch …`) are split out as commands
# of their own. On a parse failure (an unbalanced quote)
# the awk falls back to the old quote-blind split, which over-matches rather than hides.
# A parser that cannot run must not let the command through unchecked: ask the person.
if ! SEGMENTS=$(printf '%s' "$COMMAND" | awk -f "$SELF_DIR/lib/shell-segments.awk"); then
  reminder_emit_decision ask "dev-hooks guard — please confirm: the command-safety check could not run (its awk parser failed), so it cannot tell whether this command wipes data or prints a secret. Allow only if you have read it, then fix the guard: \`bash $0 < payload.json\` shows the error."
fi

# Does the segment's stdout stay out of the transcript? It does when it goes to
# /dev/null or a file, or is captured into a variable (`v=$(fnox get X)`, marked
# `=captured` by the awk). `2>/dev/null` only hides stderr, and the value goes to stdout,
# so it does not count; nor does `>&2` or `>/dev/stderr`, which still reach the screen.
seg_stdout_discarded() {
  local r
  for r in "${REDIRS[@]}"; do
    case "$r" in
      =captured) return 0 ;;
      *'>&'* | *'>/dev/std'* | *'>/dev/tty' | *'>/dev/fd/'[12]) ;;
      '>'* | '1>'* | '&>'*) return 0 ;;
    esac
  done
  return 1
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

# Does this operand resolve to a file that actually exists? A grep pattern is an operand
# too, and can look exactly like a key file (`grep event.key src/x.ts`; the quote-blind
# fallback splits `'event.key === "Escape"'` into such words as well). Requiring the
# file to exist settles it, and costs no coverage: a path that isn't there can't be
# printed either.
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
      .netrc | .pgpass | .npmrc | .pypirc | .git-credentials | \
      credentials | credentials.json | credentials.yml.enc | \
      client_secret*.json | service*account*.json | \
      secrets.json | secrets.yml | secrets.yaml) return 0 ;;
  esac
  # gh keeps its OAuth token in hosts.yml when no keyring is available, and docker its
  # registry logins in config.json when no credential store is set; the names alone are
  # too common to match without their directory.
  case "$1" in
    *gh/hosts.yml | *gh/hosts.yaml | *.docker/config.json) return 0 ;;
  esac
  return 1
}

# Is this operand a secret-shaped variable name? Matched on the name's own text, so
# $PATH and $HOME never qualify. `$` is required for echo/printf ($1 = "ref"), because
# a bare secret-shaped *word* is almost always a label reporting presence
# (`echo "BWS_ACCESS_TOKEN present"`) rather than the value; printenv takes the bare
# name as its argument, so there it is optional ($1 = "name").
#
# For a ref the match is deliberately *unanchored*, and that is the whole of the
# 2026-09-05 fix. It used to require the operand to be exactly `$VAR`, which the
# segment parser's whitespace splitting satisfied often enough to look like it worked
# — but only when a space happened to fall before the `$`. `echo "token=$API_TOKEN"`
# has no such space and sailed through, and so did every parameter expansion carrying
# a word: `${VAR:-none}` ends in `:-none}`, which the trailing `\}?$` cannot reach.
#
# That second gap is the dangerous one, because `${VAR:-word}` *looks* like a presence
# check and is the opposite of one: it yields `word` only when the variable is unset,
# so on a machine where the secret is configured it prints the secret. Written as the
# unset half of a two-branch check — `${VAR:+SET}${VAR:-UNSET}` — it reads as safe to
# everyone including its author, and it put a live BWS_ACCESS_TOKEN into a deploy
# transcript. It had even been recorded in the test suite as a false positive, which
# is why the guard had been taught to stay quiet on it.
#
# Only two expansion forms cannot print the value, and both stay silent: `+` and `:+`
# expand to the *word* rather than the variable, and `${#VAR}` is a character count.
# Everything else — `:-` `-` `:=` `=` `:?` `?`, the `:off:len` slice, and the `# % / ^ ,`
# trim and substitute operators — hands back the value or a slice of it, and four
# characters of a credential is plenty to identify it. Keeping the safe forms quiet is
# not politeness: they are what Mick should reach for instead, so nagging on them would
# push him back to the leaky one.
is_secret_var() {
  local re='[A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|APIKEY|_KEY|KEY_)[A-Za-z0-9_]*'
  if [ "$1" = name ]; then
    printf '%s' "$2" | grep -Eq "^\\\$?\\{?$re\\}?$"
    return
  fi
  # $VAR, ending at the first character that cannot continue an identifier.
  local bare="\\\$$re([^A-Za-z0-9_]|\$)"
  # ${VAR...}, unless what follows the name is `+` or `:+`. `${#VAR}` never matches
  # here at all: the `#` sits before the name, where the identifier pattern cannot
  # start.
  #
  # Identifier characters are excluded from the final alternative, and that exclusion
  # is load-bearing rather than tidy. $re ends in `[A-Za-z0-9_]*`, which a regex engine
  # is free to stop short on, so without it `${AWS_SECRET_ACCESS_KEY+present}` matched
  # by ending the name at `...KE` and reading the `Y` as the operator. Excluding them
  # forces the name to run to its own end, which is the only way the character after it
  # means anything.
  local braced="\\\$\\{$re(\\}|:[^+]|[^:+}A-Za-z0-9_])"
  printf '%s' "$2" | grep -Eq "$bare|$braced"
}

# The subcommand of a CLI with global options in front (`fnox -P prod exec`): SUB is the
# first operand, SUB_I its index in ARGS, and SUB=--help when a help or version flag comes
# first. $1 is a regex of the options that take the next word as their value.
seg_sub() {
  SUB="" SUB_I=-1
  local i=0 n=${#ARGS[@]}
  while [ "$i" -lt "$n" ]; do
    unquote "${ARGS[$i]}"
    case "$UQ" in
      -h | --help | -V | --version)
        SUB=--help
        return
        ;;
      -*)
        printf '%s' "$UQ" | grep -Eq "^($1)$" && i=$((i + 1))
        ;;
      *)
        SUB=$UQ SUB_I=$i
        return
        ;;
    esac
    i=$((i + 1))
  done
}

# Does `$1 ARGS[$2…]` print environment values? `printenv` always does here (pass
# $3=any, for a runner's child, where every variable may be a secret); otherwise only
# the forms that name nothing: bare `env`, `printenv`, `set`, `export -p`, `declare -x`.
dumps_env() {
  local name=$1 i=$2 a
  [ "$name" = printenv ] && [ "${3:-}" = any ] && return 0
  case "$name" in env | printenv | set | export | declare | typeset) ;; *) return 1 ;; esac
  while [ "$i" -lt "${#ARGS[@]}" ]; do
    a=${ARGS[$i]}
    i=$((i + 1))
    case "$name:$a" in
      env:-u | env:-C | env:-S) i=$((i + 1)) ;;
      env:*=*) ;;
      env:-i | env:-0 | env:--null | printenv:-0 | printenv:--null | env:-- | printenv:--) ;;
      export:-* | declare:-* | typeset:-*) case "$a" in *[px]*) ;; *) return 1 ;; esac ;;
      *) return 1 ;;
    esac
  done
}

# Does segment $1, the command a dump is piped into, print no secret value? Only these
# exact forms, since a looser reading of regex or sed lets whole lines through:
#   - a count or a yes/no: `wc`, `grep -c|-l|-q`;
#   - `rg -o`/`grep -o` with one anchored pattern built from literal names, groups of them
#     and the classes [A-Z_]-style, ending at most in `=` (`^(GIT_[A-Z_]+|DEV_HOOKS[A-Z_]*)=`);
#   - a grep for named variables, `^NAME=` or `^(A|B)=`, none secret-shaped or a URL;
#   - `cut -d= -f1`;
#   - `sed 's/=.*//'` (any plain replacement) or `sed -n 's/^\(NAME_[A-Z_]*\)=.*/\1/p'`.
# Sets NAME, ARGS and REDIRS, so the caller parses its own segment again.
NAME_ITEM='([A-Za-z0-9_]+|\[(A-Z|a-z|0-9|_)+\][*+]?)'
NAMES_RE="^\\^(${NAME_ITEM}|\\(${NAME_ITEM}+(\\|${NAME_ITEM}+)*\\))+=?\$"
LITERAL_NAMES_RE='^\^([A-Za-z0-9_]+|\([A-Za-z0-9_]+(\|[A-Za-z0-9_]+)*\))=$'
names_only_filter() {
  local a pat="" npat=0 o="" count="" i_flag="" s n
  seg_parse "$1"
  # rtk's proxy runs the filter as it is, only compressing its output.
  if [ "$NAME" = rtk ] && [ "${ARGS[0]:-}" = proxy ]; then
    NAME=${ARGS[1]:-}
    ARGS=("${ARGS[@]:2}")
  fi
  for a in "${REDIRS[@]}"; do
    [ "$a" = =piped ] || return 1
  done
  case "$NAME" in
    wc) return 0 ;;
    rg | grep | egrep)
      for a in "${ARGS[@]}"; do
        case "$a" in
          --count | --quiet | --files-with-matches) count=1 ;;
          --only-matching) o=1 ;;
          --extended-regexp | --perl-regexp | --no-messages) ;;
          --ignore-case) i_flag=1 ;;
          --*) return 1 ;;
          -*)
            printf '%s' "$a" | grep -Eq '^-[cloqiEPs]+$' || return 1
            case "$a" in *[clq]*) count=1 ;; esac
            case "$a" in *o*) o=1 ;; esac
            case "$a" in *i*) i_flag=1 ;; esac
            ;;
          *)
            pat=$a
            npat=$((npat + 1))
            ;;
        esac
      done
      [ -n "$count" ] && return 0
      [ "$npat" = 1 ] || return 1
      if [ -n "$o" ]; then
        printf '%s' "$pat" | grep -Eq "$NAMES_RE"
        return
      fi
      [ -z "$i_flag" ] && printf '%s' "$pat" | grep -Eq "$LITERAL_NAMES_RE" || return 1
      s=$(printf '%s' "$pat" | tr -d '^()=')
      for n in ${s//|/ }; do
        is_secret_var name "$n" && return 1
        case "$n" in *URL | *URI | *DSN) return 1 ;; esac
      done
      return 0
      ;;
    cut)
      case " ${ARGS[*]} " in
        " -d= -f1 " | " -f1 -d= " | " -d = -f1 " | " -d = -f 1 " | " -d= -f 1 " | " -f 1 -d= " | " -f1 -d = ") return 0 ;;
      esac
      return 1
      ;;
    sed)
      case "${ARGS[*]}" in
        's/=.*/'* | '-E s/=.*/'* | '-r s/=.*/'*)
          s=${ARGS[${#ARGS[@]} - 1]}
          printf '%s' "$s" | grep -Eq '^s/=\.\*/[^\\&/]*/$'
          return
          ;;
        "-n s/^\\("*)
          printf '%s' "${ARGS[1]:-}" | grep -Eq '^s/\^\\\(([A-Za-z0-9_]+|\[(A-Z|a-z|0-9|_)+\][*+]?)+\\\)=\.\*/\\1/p$' &&
            [ "${#ARGS[@]}" = 2 ]
          return
          ;;
      esac
      return 1
      ;;
    *) return 1 ;;
  esac
}

# Does the parsed stage (NAME, ARGS, REDIRS) only pass lines on to its stdout? Then a
# names-only filter after it still decides; anything that can write elsewhere (`tee`,
# `sort -o`, `awk`, `sed w`, a redirection, a /dev path) ends the walk.
passthrough_stage() {
  local a
  case "$NAME" in grep | rg | egrep | head | tail | tr | uniq | cut) ;; *) return 1 ;; esac
  for a in "${REDIRS[@]}"; do
    [ "$a" = =piped ] || return 1
  done
  for a in "${ARGS[@]}"; do
    case "$a" in */dev/*) return 1 ;; esac
  done
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
# SECRET_KIND=cred marks a credential probe (a git credential helper's `get`, gh's
# token, the desktop keyring), whose block message names the isolated way to test one.
SECRET_ASK="" SECRET_KIND=""
case "${DEV_HOOKS_GUARD_SECRETS:-deny}" in
  allow | ALLOW | off | OFF | false | FALSE | False | 0 | no | NO) ;;
  *)
    SEG_CWD="${CWD:-.}"
    # A secret runner's child is parsed like any command and appended here, with
    # RUNNER[i] naming the runner, so a dump inside it is judged in turn.
    mapfile -t SEGS <<<"$SEGMENTS"
    RUNNER=()
    for ((si = 0; si < ${#SEGS[@]}; si++)); do
      seg=${SEGS[$si]}
      seg_parse "$seg"
      [ -z "$NAME" ] && continue
      if [ "$NAME" = cd ]; then
        seg_cd
        continue
      fi
      # Output that goes nowhere can't reach the transcript.
      seg_stdout_discarded && continue
      # Piped into a filter that prints names only, a dump is how a check lists variable
      # names (`env | rg -o '^REIMBURSEMENTS_[A-Z_]+'`), so it passes.
      filtered=""
      for r in "${REDIRS[@]}"; do
        if [ "$r" = =piped ]; then
          # Down the pipe chain: once one stage keeps names only, later ones can't
          # bring values back; `tee` copies them to the screen, so the walk stops there.
          for ((sj = si + 1; sj < ${#SEGS[@]}; sj++)); do
            if names_only_filter "${SEGS[$sj]}"; then
              filtered=1
              break
            fi
            passthrough_stage || break
            case "${SEGS[$sj]}" in *"$RDM=piped"*) ;; *) break ;; esac
          done
          seg_parse "$seg"
          break
        fi
      done
      # Another process's environment, by operand or input redirection, whatever reads it:
      # `fnox exec` and `bws run` put the secrets there.
      for a in "${ARGS[@]}" "${REDIRS[@]}"; do
        unquote "${a#<}"
        case "$UQ" in
          /proc/*/env*)
            [ -n "$filtered" ] && continue
            SECRET_ASK="\`$NAME $UQ\` prints a process's environment, where \`fnox exec\` and \`bws run\` put secret values."
            break
            ;;
        esac
      done
      [ -n "$SECRET_ASK" ] && break
      if [ -z "$filtered" ] && dumps_env "$NAME" 0 "${RUNNER[$si]:+any}"; then
        if [ -n "${RUNNER[$si]:-}" ]; then
          SECRET_ASK="\`$NAME\` inside \`${RUNNER[$si]}\` prints the environment that holds the injected secrets."
        else
          SECRET_ASK="\`$NAME\` with no name prints the whole environment, which can hold tokens."
        fi
        break
      fi
      case "$NAME" in
        # BSD-style `e` (`ps e`, `auxe`, `aux e`, `-auxe`) adds every process's environment;
        # `ps -e` and `-ef` only mean "every process", and an option's value (`-C name`,
        # `-o etime`) is skipped.
        ps)
          skip=""
          for a in "${ARGS[@]}"; do
            if [ -n "$skip" ]; then
              skip=""
              continue
            fi
            case "$a" in
              -[CpuUgGoOstq] | --pid | --ppid | --user | --group | --format | --sort | --tty) skip=1 ;;
              --*) ;;
              -*) printf '%s' "$a" | grep -Eq '^-[auxwe]*e[auxwe]*$' && [ "$a" != -e ] && SECRET_ASK=1 ;;
              *) printf '%s' "$a" | grep -Eq '^[A-Za-z]*e[A-Za-z]*$' && SECRET_ASK=1 ;;
            esac
            if [ -n "$SECRET_ASK" ]; then
              SECRET_ASK="\`ps $a\` prints other processes' environments, where \`fnox exec\` puts secret values. Use \`ps -o pid,ppid,comm,etime\` instead."
              break
            fi
          done
          ;;
        # An allowlist, not a denylist: a new or overlooked subcommand that prints values
        # (fnox's env, export, edit, tui, mcp, lease) is refused until it is listed here.
        fnox | bws)
          if [ "$NAME" = fnox ]; then
            seg_sub '-c|--config|-P|--profile|--if-missing|--write-profile'
          else
            seg_sub '-o|--output|-c|--color|-t|--access-token|-f|--config-file|-p|--profile|-u|--server-url'
          fi
          for a in "${ARGS[@]}"; do
            case "$a" in --) break ;; -h | --help) SUB=--help ;; esac
          done
          case "$NAME:$SUB" in
            *:--help | *: | fnox:check | fnox:c | fnox:list | fnox:ls | fnox:secrets | \
              fnox:config-files | fnox:profiles | fnox:doctor | fnox:dr | fnox:scan | fnox:audit | \
              fnox:completion | fnox:daemon | fnox:activate | fnox:deactivate | fnox:import | fnox:im | \
              fnox:init | fnox:i | fnox:plugin | fnox:provider | fnox:proxy | fnox:reencrypt | \
              fnox:remove | fnox:rm | fnox:delete | fnox:set | fnox:s | fnox:sync | fnox:sponsors | \
              fnox:version | fnox:v | fnox:help | bws:project | bws:config | bws:completions | bws:help) ;;
            fnox:exec | fnox:x | fnox:run | bws:run)
              # The child: after `--`, else after the runner's own options (bws run also
              # takes it as one string). It is parsed like any command and judged in turn.
              i=$((SUB_I + 1)) dashes=""
              for ((j = i; j < ${#ARGS[@]}; j++)); do
                if [ "${ARGS[$j]}" = -- ]; then
                  i=$((j + 1)) dashes=1
                  break
                fi
              done
              while [ -z "$dashes" ] && [ "$i" -lt "${#ARGS[@]}" ]; do
                case "${ARGS[$i]}" in
                  -P | --profile | -c | --config | --if-missing | --write-profile | --project-id | \
                    -o | --output | -t | --access-token | -f | --config-file | -p | -u | --server-url) i=$((i + 2)) ;;
                  -*) i=$((i + 1)) ;;
                  *) break ;;
                esac
              done
              child=""
              if [ "$NAME" = bws ] && [ $((i + 1)) -eq "${#ARGS[@]}" ]; then
                child=${ARGS[$i]//$'\036'/$'\n'}
              else
                for a in "${ARGS[@]:$i}"; do
                  a=${a//$'\036'/$'\n'}
                  child+="'${a//\'/\'\\\'\'}' "
                done
              fi
              while IFS= read -r c; do
                [ -z "$c" ] && continue
                SEGS+=("$c")
                RUNNER[${#SEGS[@]} - 1]="$NAME $SUB"
              done < <(printf '%s' "$child" | awk -f "$SELF_DIR/lib/shell-segments.awk")
              ;;
            bws:secret)
              seg_words
              case "$WORDS" in 'secret delete '*) continue ;; esac
              # The last -o wins, as with any repeated option.
              out=""
              for ((j = 0; j < ${#ARGS[@]}; j++)); do
                case "${ARGS[$j]}" in
                  -o | --output) out=${ARGS[$((j + 1))]:-} ;;
                  --output=*) out=${ARGS[$j]#--output=} ;;
                  -o?*) out=${ARGS[$j]#-o} ;;
                esac
              done
              [ "$out" = none ] && continue
              SECRET_ASK="\`bws ${WORDS% }\` prints secret values to stdout."
              case "$WORDS" in 'secret create '* | 'secret edit '*) SECRET_ASK="${SECRET_ASK%.}; add \`-o none\` when only the write matters." ;; esac
              ;;
            *)
              ex="exec"
              [ "$NAME" = bws ] && ex=run
              SECRET_ASK="\`$NAME $SUB\` can print secret values: only $NAME commands known not to (such as \`$NAME $ex\`) pass this guard."
              ;;
          esac
          ;;
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
          # Operands, plus the file of an input redirection (`cat < .env`).
          files=()
          for a in "${ARGS[@]}"; do
            case "$a" in -*) continue ;; esac
            files+=("$a")
          done
          for a in "${REDIRS[@]}"; do
            case "$a" in '<<'* | '<&'* | '<>'*) ;; '<'*) files+=("${a#<}") ;; esac
          done
          for a in "${files[@]}"; do
            unquote "$a"
            if path_is_secret "$UQ" && file_exists "$UQ"; then
              SECRET_ASK="\`$NAME $UQ\` prints the contents of a file that holds secret values."
              case "$UQ" in *.git-credentials | *gh/hosts.y*ml | *.docker/config.json) SECRET_KIND=cred ;; esac
              break
            fi
          done
          ;;
        op | vault | gh | glab | aws | az | gcloud | doppler | kubectl | pass | secret-tool | security)
          seg_words
          case "$NAME:$WORDS" in
            op:'read '* | op:'item get '* | \
              vault:'kv get '* | vault:'read '* | \
              aws:'secretsmanager get-secret-value '* | aws:'ssm get-parameter '* | \
              doppler:'secrets get '* | doppler:'secrets download '* | \
              kubectl:'get secret '* | kubectl:'get secrets '* | \
              pass:'show '*)
              SECRET_ASK="\`$NAME\` prints the secret's value to stdout."
              ;;
            # gh's token, and the credential helper `git credential fill` calls.
            gh:'auth token '* | gh:'auth git-credential get '*)
              SECRET_ASK="\`gh ${WORDS% }\` prints your GitHub token."
              SECRET_KIND=cred
              ;;
            gh:'auth status '* | glab:'auth status '*)
              forge=GitHub
              [ "$NAME" = glab ] && forge=GitLab
              for a in "${ARGS[@]}"; do
                case "$a" in
                  -t | --show-token | --show-token=true)
                    SECRET_ASK="\`$NAME auth status $a\` prints your $forge token unmasked."
                    SECRET_KIND=cred
                    ;;
                esac
              done
              ;;
            az:'account get-access-token '* | gcloud:'auth print-access-token '* | \
              gcloud:'auth print-identity-token '* | gcloud:'auth application-default print-access-token '*)
              SECRET_ASK="\`$NAME ${WORDS% }\` prints a cloud access token."
              SECRET_KIND=cred
              ;;
            # The desktop keyring: `lookup` prints the secret, `search` prints each match's.
            secret-tool:'lookup '* | secret-tool:'search '*)
              SECRET_ASK="\`secret-tool ${WORDS%% *}\` prints a secret from your keyring."
              SECRET_KIND=cred
              ;;
            # The macOS keychain prints the password itself with -w (stdout) or -g (stderr).
            security:'find-generic-password '* | security:'find-internet-password '*)
              for a in "${ARGS[@]}"; do
                case "$a" in
                  --*) ;;
                  -*[wg]*)
                    SECRET_ASK="\`security ${WORDS%% *} $a\` prints a password from your keychain."
                    SECRET_KIND=cred
                    ;;
                esac
              done
              ;;
          esac
          ;;
        # A credential helper's `get` prints the password it holds: `git credential fill`
        # runs every configured helper, `git credential-<helper> get` and
        # `git-credential-<helper> get` call one directly. approve/reject/store/erase only
        # read a credential from stdin, and print nothing.
        git)
          seg_git_sub
          case "$GIT_SUB" in
            credential)
              [ "${GIT_REST[0]:-}" = fill ] && SECRET_ASK="\`git credential fill\` asks your credential helpers for a password and prints it."
              ;;
            credential-*)
              for a in "${GIT_REST[@]}"; do
                [ "$a" = get ] && SECRET_ASK="\`git $GIT_SUB get\` prints the password that credential helper holds."
              done
              ;;
          esac
          [ -n "$SECRET_ASK" ] && SECRET_KIND=cred
          ;;
        git-credential-* | docker-credential-*)
          for a in "${ARGS[@]}"; do
            if [ "$a" = get ]; then
              SECRET_ASK="\`$NAME get\` prints the password that credential helper holds."
              SECRET_KIND=cred
            fi
          done
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
    done
    ;;
esac

if [ -n "$SECRET_ASK" ]; then
  REASON="dev-hooks guard — $SECRET_ASK Anything printed here enters the transcript, where it is logged and summarised, and the only real fix is rotating the credential."
  if [ "$SECRET_KIND" = cred ]; then
    # On 2026-10-02 `PATH=/usr/bin:/bin git credential fill`, meant to test a "gh
    # missing" case, reached the laptop's logged-in /usr/bin/gh and printed a live token.
    # Inline variables are not accepted as isolation: a repo's own .git/config, a helper
    # named by absolute path, and the desktop keyring all survive them, and a parser that
    # tried to judge them would be one more thing to get wrong.
    REASON="$REASON To test credential plumbing, cut it off from the real stores — a temp \`HOME\`, \`GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1\`, a temp \`GH_CONFIG_DIR\`, empty \`GH_TOKEN\`/\`GITHUB_TOKEN\`/\`SSH_AUTH_SOCK\`, and a PATH with a fake \`gh\` first — and never print the helper's output (count its bytes or redact it). Setting those variables inline here is not trusted, since a repo's own .git/config, a helper named by absolute path and the desktop keyring survive them: write the probe into a test script that builds that isolation, or ask the user to run it outside the agent."
  else
    REASON="$REASON Use a form that doesn't print the value: \`\${VAR:+SET}\` or \`\${#VAR}\` for a presence check (\`\${VAR:-UNSET}\` prints the value — it is NOT a presence check), \`fnox exec\`/\`bws run\` to inject it, \`--output\` to a gitignored file, or ask the user to check it themselves."
  fi
  case "${DEV_HOOKS_GUARD_SECRETS:-deny}" in
    ask | ASK | Ask)
      reminder_emit_decision ask "$REASON Confirm if you do need to see it."
      ;;
    *)
      reminder_emit_decision deny "BLOCKED: $REASON If you genuinely need the value on screen, run it yourself outside the agent."
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
      # The repo the command acts on, not the session's: `cd repo && git commit`, `git -C repo push`.
      if [ -n "$GIT_COMMITS" ]; then reminder_git_target_dir commit; else reminder_git_target_dir push; fi
      branch=$(git -C "$REPLY" branch --show-current 2>/dev/null)
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
