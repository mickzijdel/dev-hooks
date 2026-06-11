#!/bin/bash
# getting-started onboarding audit.
#
# Reports what a beginner's machine already has so the skill can install or upgrade only
# what's missing — making the whole setup idempotent and re-runnable. Read-only: it detects,
# it never installs.
#
# Usage: onboard_check.sh
#
# Emits machine-readable KEY=VALUE lines on stdout, followed by "# " summary lines. Keys:
#   os               macos | linux | wsl | unknown
#   arch             uname -m (arm64, x86_64, …)
#   pkg_mgr          brew | apt | dnf | pacman | zypper | none  (system/GUI package manager)
#   <tool>           installed | missing   for each CLI tool we set up
#   <tool>_version   the detected version string (only when installed)
#   gh_auth          yes | no | unknown   (logged in to GitHub?)
#   git_identity     yes | no             (user.name AND user.email configured globally?)
#   playwright_browsers  installed | missing  (chromium present in the Playwright cache?)
#
# Currency ("is it outdated?") is intentionally NOT computed here — the mise-managed tools are
# upgraded as a group with `mise upgrade`, and querying every registry would be slow and
# network-bound. The skill workflow handles upgrades.

set -u

# ── OS / arch / package manager ──────────────────────────────────────────────────
arch="$(uname -m 2>/dev/null || echo unknown)"
os="unknown"
case "$(uname -s 2>/dev/null)" in
  Darwin) os="macos" ;;
  Linux)
    os="linux"
    # WSL reports a Microsoft-flavoured kernel.
    if grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease /proc/version 2>/dev/null; then
      os="wsl"
    fi
    ;;
esac

pkg_mgr="none"
for m in brew apt-get dnf pacman zypper; do
  if command -v "$m" >/dev/null 2>&1; then
    case "$m" in
      apt-get) pkg_mgr="apt" ;;
      *) pkg_mgr="$m" ;;
    esac
    break
  fi
done

# ── Per-tool presence + version ──────────────────────────────────────────────────
# report KEY COMMAND [VERSION_ARGS...] — prints "KEY=installed" + "KEY_version=…" or
# "KEY=missing". The version is the first line of `COMMAND --version`, trimmed.
report() {
  local key="$1" cmd="$2"
  shift 2
  if command -v "$cmd" >/dev/null 2>&1; then
    local v
    v="$("$cmd" "${@:---version}" 2>/dev/null | head -n1 | tr -d '\r')"
    echo "${key}=installed"
    [ -n "$v" ] && echo "${key}_version=${v}"
  else
    echo "${key}=missing"
  fi
}

# OS / context first.
echo "os=$os"
echo "arch=$arch"
echo "pkg_mgr=$pkg_mgr"

report claude claude
report git git
report mise mise
report node node
report pnpm pnpm
report python python3
report uv uv
report jq jq
report ripgrep rg
report gitleaks gitleaks
report gh gh
report docker docker
report code code # VS Code CLI

# ── GitHub auth ──────────────────────────────────────────────────────────────────
gh_auth="unknown"
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    gh_auth="yes"
  else
    gh_auth="no"
  fi
fi
echo "gh_auth=$gh_auth"

# ── git identity (commits need a name + email) ───────────────────────────────────
git_identity="no"
if command -v git >/dev/null 2>&1; then
  gname="$(git config --global user.name 2>/dev/null)"
  gemail="$(git config --global user.email 2>/dev/null)"
  [ -n "$gname" ] && [ -n "$gemail" ] && git_identity="yes"
fi
echo "git_identity=$git_identity"

# ── Playwright browser cache (chromium) — vischeck's prerequisite ────────────────
playwright_browsers="missing"
for d in "$HOME/.cache/ms-playwright" "$HOME/Library/Caches/ms-playwright"; do
  if [ -d "$d" ] && find "$d" -maxdepth 1 -type d -name 'chromium*' 2>/dev/null | grep -q .; then
    playwright_browsers="installed"
    break
  fi
done
echo "playwright_browsers=$playwright_browsers"

# ── Human-readable summary ───────────────────────────────────────────────────────
echo "# OS: $os ($arch); system package manager: $pkg_mgr"
case "$os" in
  unknown) echo "# Could not identify the OS — the skill targets macOS, Linux, and WSL2 (bash). On native Windows, install WSL2 first and re-run inside it." ;;
  wsl) echo "# Running under WSL2 — install Linux tools here; Docker Desktop/VS Code live on the Windows side." ;;
esac

exit 0
