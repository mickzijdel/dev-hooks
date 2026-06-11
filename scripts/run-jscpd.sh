#!/usr/bin/env bash
# Shared jscpd runner — the single home of the version-cooldown policy, called by both
# hk.pkl (pre-commit / `hk check`) and the CI audit job so the local and CI gates
# can't drift. Scan scope/config (minTokens/threshold/reporters) lives in .jscpd.json;
# `-f python,bash` restricts detection to real code (see hk.pkl for the rationale).
#
# Version policy: track latest with a 4-day cooldown (never run a release < 4 days old —
# supply-chain seasoning), floored at v5 (the major .jscpd.json targets) so it can't
# regress to v4 while v5 is still maturing. Online → resolve the newest version >= 4 days
# old (`npx --before`), fall back to `latest` when that lands below the v5 floor, then run
# it (the real gate — exit reflects duplication). Offline → run the cached jscpd. No cache
# + offline → warn and pass, so a commit is never blocked by an unreachable registry —
# except under --require (CI passes it): there an unrunnable jscpd fails the job rather
# than silently skipping the duplication gate.
set -u

require=0
[ "${1:-}" = "--require" ] && require=1

cutoff=$(date -u -d '4 days ago' +%F 2>/dev/null || date -u -v-4d +%F)
if curl -sf -m 3 https://registry.npmjs.org/ >/dev/null 2>&1; then
  ver=$(npx --before="$cutoff" --yes jscpd --version 2>/dev/null | awk 'END{print $NF}')
  case $ver in
    '' | 0.* | 1.* | 2.* | 3.* | 4.*) ver=latest ;;
  esac
  npx --yes jscpd@"$ver" . -f python,bash
elif npx --offline jscpd --version >/dev/null 2>&1; then
  npx --offline jscpd . -f python,bash
else
  if [ "$require" = 1 ]; then
    echo 'jscpd unavailable (offline, no cache) and --require set; failing' >&2
    exit 1
  fi
  echo 'jscpd unavailable offline; skipping duplication check'
fi
