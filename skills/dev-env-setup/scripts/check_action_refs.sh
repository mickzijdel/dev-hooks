#!/bin/bash
# Verify every GitHub Actions `uses: OWNER/REPO@REF` pins a ref that actually resolves
# on the remote — catching the class of break where CI fails at "Prepare all required
# actions" with "Unable to resolve action … unable to find version `vN`".
#
# Why this exists: an action can publish release tags (v8.0.0, v8.1.0, …) without floating
# a `@v8` *major* tag. Pinning `@v8` then looks fine locally but errors only when CI runs.
# This script checks resolution up front, so Claude/you catch it before pushing instead of
# waiting for the red CI run.
#
# Usage:  check_action_refs.sh [PATH ...]
#   PATH is a workflow file or a directory scanned recursively for *.yml/*.yaml.
#   Default when no PATH is given: ./.github/workflows
#
# For each unique ref it runs `git ls-remote` against the action's repo and classifies:
#   OK    — ref exists as a tag or branch on the remote
#   FAIL  — remote is reachable but has no such tag/branch (the CI-breaking case)
#   PIN   — ref is a commit SHA (cannot be listed via ls-remote; reported, not failed)
#   SKIP  — remote could not be reached (offline / private); not counted as a failure
# Exit status: 1 if any FAIL, else 0. Network errors never fail the run (SKIP).
#
# Testing/advanced seam: set DEV_HOOKS_LSREMOTE to override the `git ls-remote` command
# (e.g. a stub) — it is invoked as `<cmd> <repo-url> refs/tags/<ref> refs/heads/<ref>`.

set -u

# Resolver command (array so a multi-word default stays shellcheck-clean).
read -r -a LSREMOTE <<<"${DEV_HOOKS_LSREMOTE:-git ls-remote}"

# ── Collect target files ────────────────────────────────────────────────────────────
files=()
if [ "$#" -eq 0 ]; then
  if [ -d .github/workflows ]; then
    while IFS= read -r f; do files+=("$f"); done < <(find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
  else
    echo "check_action_refs: no PATH given and ./.github/workflows not found" >&2
    echo "usage: check_action_refs.sh [PATH ...]" >&2
    exit 2
  fi
else
  for p in "$@"; do
    if [ -d "$p" ]; then
      while IFS= read -r f; do files+=("$f"); done < <(find "$p" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
    elif [ -f "$p" ]; then
      files+=("$p")
    else
      echo "check_action_refs: no such file or directory: $p" >&2
      exit 2
    fi
  done
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "No workflow files found."
  exit 0
fi

# ── Extract unique OWNER/REPO[/subdir]@REF references ───────────────────────────────
# Skips local (`./…`) and docker (`docker://…`) uses; those have no remote ref to check.
mapfile -t refs < <(
  grep -rhoE 'uses:[[:space:]]*["'"'"']?[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[^[:space:]"'"'"']+' "${files[@]}" 2>/dev/null |
    sed -E 's/^uses:[[:space:]]*["'"'"']?//' | sort -u
)

if [ "${#refs[@]}" -eq 0 ]; then
  echo "No GitHub Actions \`uses: owner/repo@ref\` references found."
  exit 0
fi

# ── Resolve each ref ────────────────────────────────────────────────────────────────
ok=0
fail=0
pin=0
skip=0
fail_lines=""

for ref in "${refs[@]}"; do
  path="${ref%@*}" # owner/repo[/subdir]
  tag="${ref#*@}"  # the ref
  repo="$(printf '%s' "$path" | cut -d/ -f1-2)"
  url="https://github.com/$repo"

  # A pinned commit SHA (7–40 hex chars) can't be listed via ls-remote — report, don't fail.
  if printf '%s' "$tag" | grep -qE '^[0-9a-f]{7,40}$'; then
    printf 'PIN   %s  (commit SHA, not verified)\n' "$ref"
    pin=$((pin + 1))
    continue
  fi

  out="$("${LSREMOTE[@]}" "$url" "refs/tags/$tag" "refs/heads/$tag" 2>/dev/null)"
  rc=$?

  if [ "$rc" -ne 0 ]; then
    printf 'SKIP  %s  (could not reach %s)\n' "$ref" "$url"
    skip=$((skip + 1))
  elif [ -n "$out" ]; then
    printf 'OK    %s\n' "$ref"
    ok=$((ok + 1))
  else
    printf 'FAIL  %s  (no such tag or branch on %s)\n' "$ref" "$url"
    fail_lines+="  $ref"$'\n'
    fail=$((fail + 1))
  fi
done

# ── Summary ─────────────────────────────────────────────────────────────────────────
echo "---"
printf '%d ok, %d unresolved, %d pinned-sha, %d unreachable\n' "$ok" "$fail" "$pin" "$skip"

if [ "$fail" -gt 0 ]; then
  echo "Unresolved refs must be fixed — they will break CI at \"Prepare all required actions\":"
  printf '%s' "$fail_lines"
  echo "Pin a ref that exists (often the exact release tag, e.g. @v8.2.0, when no floating major is published)."
  exit 1
fi
exit 0
