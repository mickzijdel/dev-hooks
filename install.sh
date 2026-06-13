#!/bin/bash
# coding-onboarding bootstrap — get a complete beginner from "nothing installed" to
# "talking to Claude with the onboarding skill running".
#
# Run it with one line (nothing needs to be installed first):
#
#   curl -fsSL https://raw.githubusercontent.com/mickzijdel/dev-hooks/main/install.sh | bash
#
# It does only the handful of things that CAN'T be done from inside Claude:
#   1. opens a checklist page in your browser so you can follow along
#   2. installs Claude Code (the AI helper) if it's missing
#   3. helps you sign in
#   4. adds the add-on ("plugin") that teaches Claude how to set up the rest of your machine
#   5. hands you off to Claude, where you just type:  set me up
#
# Everything else (the programming toolbox, GitHub, the editor, Docker) happens *inside*
# Claude, where it can explain each step to you as it goes.
#
# Safe to re-run: anything already done is detected and skipped.
#
# For testers / power users (env seams, all optional):
#   ONBOARD_CLAUDE_BIN   path to the `claude` binary (default: found on your PATH)
#   ONBOARD_ASSUME_YES=1 don't pause for "press Enter" — run straight through
#   ONBOARD_NO_BROWSER=1 don't download/open the checklist page
#   --check              read-only: report what's set up as KEY=VALUE lines, then exit

set -u

# ── Constants ───────────────────────────────────────────────────────────────────────
REPO="mickzijdel/dev-hooks"
RAW_BASE="https://raw.githubusercontent.com/mickzijdel/dev-hooks/main"
HTML_PATH="plugins/coding-onboarding/onboarding/onboard.html"
TROUBLESHOOT_URL="${RAW_BASE}/plugins/coding-onboarding/skills/getting-started/references/troubleshooting.md"
CLAUDE_INSTALL_URL="https://claude.ai/install.sh"
MARKETPLACE="$REPO"
PLUGIN="coding-onboarding@dev-hooks"
TOTAL_STEPS=5

# ── Pretty output (plain words, no jargon) ───────────────────────────────────────────
if [ -t 1 ]; then
  B=$'\033[1m'
  DIM=$'\033[2m'
  OK=$'\033[32m'
  WARN=$'\033[33m'
  R=$'\033[0m'
else
  B=""
  DIM=""
  OK=""
  WARN=""
  R=""
fi

# Can we ask the user questions? When run as `curl ... | bash`, normal input is the
# download stream, so we talk to the keyboard directly via /dev/tty.
HAVE_TTY=0
# Actually try to open /dev/tty for read AND write — the permission-bit tests (-r/-w) pass even
# when the device node exists but has no terminal behind it (the curl|bash-in-CI case, where
# opening it fails with "No such device or address").
if { true >/dev/tty; } 2>/dev/null && { true </dev/tty; } 2>/dev/null; then HAVE_TTY=1; fi

ASSUME_YES="${ONBOARD_ASSUME_YES:-}"

# pause — wait for the user to press Enter before doing something. Degrades to "just keep
# going" when there's no keyboard attached (or ONBOARD_ASSUME_YES is set), so the script
# never hangs forever in an automated run.
pause() {
  if [ -n "$ASSUME_YES" ] || [ "$HAVE_TTY" -ne 1 ]; then
    [ "$HAVE_TTY" -ne 1 ] && printf '%s(no keyboard input available — continuing automatically)%s\n' "$DIM" "$R"
    return 0
  fi
  printf '%sPress Enter when you are ready…%s ' "$DIM" "$R"
  read -r _ </dev/tty
}

# explain — a clearly separated banner for each step: which step, a plain-words title, and a
# short "what this is / why you need it" note, then a pause.
explain() {
  local n="$1" title="$2" body="$3"
  printf '\n%s──────────────────────────────────────────────%s\n' "$DIM" "$R"
  printf '%sStep %s of %s · %s%s\n' "$B" "$n" "$TOTAL_STEPS" "$title" "$R"
  printf '%s\n' "$body"
  pause
}

done_already() { printf '%s✓ already done%s — %s\n' "$OK" "$R" "$1"; }
say() { printf '%s\n' "$1"; }

# fail_friendly — never dump a raw error at a beginner. Say what happened in plain words,
# reassure, and give one concrete next step.
fail_friendly() {
  printf '\n%sSomething did not go through.%s %s\n' "$WARN" "$R" "$1"
  say "This is not your fault — it usually means a download was interrupted."
  say "Try running the same command again. If it keeps happening, see:"
  say "  $TROUBLESHOOT_URL"
}

# ── OS detection ─────────────────────────────────────────────────────────────────────
# Returns one of: macos | linux | wsl | windows | unknown. (Deliberately its own minimal
# form — the skill's onboard_check.sh does a fuller probe; we only need the broad family.)
detect_os() {
  local kernel
  kernel="$(uname -s 2>/dev/null || true)"
  if [ "$kernel" = "Darwin" ]; then
    say "macos"
  elif [ "$kernel" = "Linux" ]; then
    if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then say "wsl"; else say "linux"; fi
  else
    case "$kernel" in
      CYGWIN* | MINGW* | MSYS*) say "windows" ;;
      *) say "unknown" ;;
    esac
  fi
}

# ── claude binary resolution + tiny query helpers ────────────────────────────────────
CLAUDE_BIN="${ONBOARD_CLAUDE_BIN:-}"
resolve_claude() {
  # An explicit ONBOARD_CLAUDE_BIN is honoured exactly — no PATH fallback — so it's a
  # faithful test seam and so a deliberate override is never silently ignored.
  if [ -n "${ONBOARD_CLAUDE_BIN:-}" ]; then
    command -v "$CLAUDE_BIN" >/dev/null 2>&1 && return 0
    CLAUDE_BIN=""
    return 1
  fi
  if command -v claude >/dev/null 2>&1; then
    CLAUDE_BIN="claude"
    return 0
  fi
  CLAUDE_BIN=""
  return 1
}

claude_logged_in() {
  [ -n "$CLAUDE_BIN" ] || return 1
  "$CLAUDE_BIN" auth status --json 2>/dev/null | grep -q '"loggedIn":[[:space:]]*true'
}
marketplace_present() {
  [ -n "$CLAUDE_BIN" ] || return 1
  "$CLAUDE_BIN" plugin marketplace list --json 2>/dev/null | grep -q '"dev-hooks"'
}
plugin_present() {
  [ -n "$CLAUDE_BIN" ] || return 1
  "$CLAUDE_BIN" plugin list --json 2>/dev/null | grep -q '"coding-onboarding"'
}

# ── --check : read-only report, used by tests and the curious ─────────────────────────
if [ "${1:-}" = "--check" ]; then
  resolve_claude && claude_state="installed" || claude_state="missing"
  [ "$HAVE_TTY" -eq 1 ] && tty_state="yes" || tty_state="no"
  if [ "$claude_state" = "installed" ]; then
    claude_logged_in && login_state="yes" || login_state="no"
    marketplace_present && mkt_state="present" || mkt_state="missing"
    plugin_present && plug_state="present" || plug_state="missing"
  else
    login_state="unknown"
    mkt_state="unknown"
    plug_state="unknown"
  fi
  echo "os=$(detect_os)"
  echo "tty=$tty_state"
  echo "claude=$claude_state"
  echo "logged_in=$login_state"
  echo "marketplace=$mkt_state"
  echo "plugin=$plug_state"
  exit 0
fi

# ── Welcome ──────────────────────────────────────────────────────────────────────────
OS="$(detect_os)"
printf '\n%s  Welcome! Let us set up your computer for coding with Claude.%s\n' "$B" "$R"
say ""
say "  You don't need to know anything about coding yet. This sets up an AI helper"
say "  called Claude that will do the rest of the setup *with* you, explaining as it goes."
say ""
say "  • Takes about 5 minutes here, then a bit more inside Claude."
say "  • You'll need a free Claude account (you'll sign in during this)."
say "  • It's safe to run this again any time — finished steps are skipped."
say ""

# Native Windows can't run this script directly — it needs the small Linux workspace (WSL2).
if [ "$OS" = "windows" ] || [ "$OS" = "unknown" ]; then
  printf '%sUsing Windows? One thing first.%s\n' "$B" "$R"
  say "Most coding tools expect a small Linux workspace inside Windows, called WSL2."
  say "Setting it up is two steps:"
  say "  1. Open PowerShell as Administrator and run:   wsl --install"
  say "  2. Restart your computer, open \"Ubuntu\" from the Start menu, and paste this"
  say "     same command there."
  say ""
  say "The checklist page has pictures and more detail:"
  say "  ${RAW_BASE}/${HTML_PATH}"
  exit 1
fi

# ── Step 1 · checklist page ──────────────────────────────────────────────────────────
explain 1 "Open a checklist to follow along" \
  "A page will open in your web browser with these steps as a tick-list. Keep it next to
this window so you can see where you are. (If nothing opens, that's fine — I'll print a
link you can open yourself.)"
if [ -n "${ONBOARD_NO_BROWSER:-}" ]; then
  say "(skipping the browser page)"
else
  html_tmp="$(mktemp -t onboard-XXXXXX 2>/dev/null).html"
  if curl -fsSL "${RAW_BASE}/${HTML_PATH}" -o "$html_tmp" 2>/dev/null; then
    opened=0
    for opener in open xdg-open wslview; do
      if command -v "$opener" >/dev/null 2>&1; then
        "$opener" "$html_tmp" >/dev/null 2>&1 && opened=1 && break
      fi
    done
    if [ "$opened" -eq 1 ]; then
      done_already "checklist opened in your browser"
    else
      say "Open this file in your browser to follow along:  $html_tmp"
    fi
  else
    say "Could not download the checklist — no problem, open this link in your browser:"
    say "  ${RAW_BASE}/${HTML_PATH}"
  fi
fi

# ── Step 2 · Claude Code ─────────────────────────────────────────────────────────────
explain 2 "Install Claude Code, your AI helper" \
  "Claude Code is an AI assistant that lives in this window and can set things up for you.
It's the tool that does the rest of this onboarding with you. I'll download and install it
now if it isn't already here."
if resolve_claude; then
  done_already "Claude Code is installed ($("$CLAUDE_BIN" --version 2>/dev/null | head -n1))"
else
  say "Downloading and installing Claude Code…"
  if curl -fsSL "$CLAUDE_INSTALL_URL" | bash; then
    export PATH="$HOME/.local/bin:$PATH"
    if resolve_claude; then
      done_already "Claude Code installed ($("$CLAUDE_BIN" --version 2>/dev/null | head -n1))"
    else
      fail_friendly "Claude Code installed but I can't find it on this terminal yet."
      say "Close this window, open a new one, and run the command again."
      exit 1
    fi
  else
    fail_friendly "The Claude Code download didn't finish."
    exit 1
  fi
fi

# ── Step 3 · sign in ─────────────────────────────────────────────────────────────────
explain 3 "Sign in to Claude" \
  "Just like any app, Claude needs you to sign in so it knows it's you. A web browser
window will open for you to log in (or create a free account). Your code always stays on
your own computer."
if claude_logged_in; then
  done_already "you're signed in to Claude"
elif [ "$HAVE_TTY" -eq 1 ]; then
  "$CLAUDE_BIN" auth login </dev/tty >/dev/tty 2>&1 || say "$(printf '%sSign-in didn'\''t complete — you can do it later by running: claude%s' "$WARN" "$R")"
else
  say "When this finishes, type  claude  and press Enter to sign in."
fi

# ── Step 4 · the onboarding add-on ───────────────────────────────────────────────────
explain 4 "Add the setup guide to Claude" \
  "Claude can learn new skills through add-ons (think of installing an app on a phone; the
\"marketplace\" is the app store they come from). I'll add the one that knows how to set up
the rest of your machine, step by step."
if marketplace_present; then
  done_already "the add-on store is already connected"
else
  say "Connecting the add-on store…"
  "$CLAUDE_BIN" plugin marketplace add "$MARKETPLACE" || fail_friendly "Couldn't connect the add-on store."
fi
if plugin_present; then
  done_already "the setup guide is already installed"
else
  say "Installing the setup guide…"
  "$CLAUDE_BIN" plugin install "$PLUGIN" || fail_friendly "Couldn't install the setup guide."
fi

# ── Step 5 · hand off ────────────────────────────────────────────────────────────────
explain 5 "Start Claude and let it finish the setup" \
  "That's everything I can do out here. From now on Claude takes over and walks you through
the rest — installing your coding toolbox, connecting GitHub, your editor, and more —
explaining each piece in plain language."
say ""
printf '%s  ┌────────────────────────────────────────────────┐%s\n' "$B" "$R"
printf '%s  │  Next:                                          │%s\n' "$B" "$R"
printf '%s  │    1. type:  claude   and press Enter           │%s\n' "$B" "$R"
printf '%s  │    2. when Claude answers, type:  set me up     │%s\n' "$B" "$R"
printf '%s  └────────────────────────────────────────────────┘%s\n' "$B" "$R"
say ""

if [ "$HAVE_TTY" -eq 1 ] && [ -z "$ASSUME_YES" ] && [ -n "$CLAUDE_BIN" ]; then
  printf '%sPress Enter to start Claude now (or Ctrl-C to do it yourself later)…%s ' "$DIM" "$R"
  read -r _ </dev/tty
  exec "$CLAUDE_BIN" </dev/tty
fi
