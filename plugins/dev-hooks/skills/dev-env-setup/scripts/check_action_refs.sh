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
#   OK    — a tag/branch ref resolves, OR a SHA pin carrying a `# vX.Y.Z` comment matches the
#           commit that tag points to on the remote (the pin is honest)
#   FAIL  — the ref doesn't exist, or a SHA pin's `# vX.Y.Z` comment names a tag whose commit
#           differs from the pinned SHA (a lying / stale pin) — the CI-breaking or audit case
#   PIN   — a commit SHA with no `# vX.Y.Z` comment (cannot be verified; reported, not failed)
#   SKIP  — remote could not be reached (offline / private); not counted as a failure
# Exit status: 1 if any FAIL, else 0. Network errors never fail the run (SKIP).
#
# Testing/advanced seam: set DEV_HOOKS_LSREMOTE to override the `git ls-remote` command (e.g. a
# stub) — invoked as `<cmd> <repo-url> refs/tags/<ref> refs/heads/<ref>` for a tag/branch ref,
# or `<cmd> <repo-url> refs/tags/<tag> refs/tags/<tag>^{}` to resolve a SHA pin's comment.

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

# ── Extract unique `uses:` references (ref + optional `# vX.Y.Z` version comment) ────
# Skips local (`./…`) and docker (`docker://…`) uses; those have no remote ref to check.
# The trailing comment is captured so a SHA pin written `owner/repo@<sha> # v1.2.3` can be
# verified against the tag the comment claims it is.
mapfile -t uses_lines < <(
  grep -rhoE 'uses:[[:space:]]*["'"'"']?[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[^[:space:]"'"'"']+([[:space:]]*#.*)?' "${files[@]}" 2>/dev/null |
    sort -u
)

if [ "${#uses_lines[@]}" -eq 0 ]; then
  echo "No GitHub Actions \`uses: owner/repo@ref\` references found."
  exit 0
fi

# Parse each line into "<ref>\t<comment-tag>" (tag empty when there's no `# vX.Y.Z`) and dedupe.
records=()
for line in "${uses_lines[@]}"; do
  rest="${line#*uses:}"                   # drop the `uses:` key
  rest="${rest#"${rest%%[![:space:]]*}"}" # ltrim
  rest="${rest#\"}"
  rest="${rest#\'}"
  ref="${rest%%[[:space:]]*}" # first token: owner/repo@ref
  ref="${ref%\"}"
  ref="${ref%\'}"
  tag=""
  case "$rest" in
    *"#"*)
      comment="${rest#*#}"
      tag="$(printf '%s' "$comment" | grep -oiE 'v[0-9][0-9A-Za-z._-]*' | head -1)"
      ;;
  esac
  records+=("$ref"$'\t'"$tag")
done
mapfile -t records < <(printf '%s\n' "${records[@]}" | sort -u)

# ── Resolve / verify each ref ───────────────────────────────────────────────────────
ok=0
fail=0
pin=0
skip=0
fail_lines=""

for record in "${records[@]}"; do
  ref="${record%%$'\t'*}"
  tag="${record#*$'\t'}"
  path="${ref%@*}"   # owner/repo[/subdir]
  pinref="${ref#*@}" # the SHA or tag
  repo="$(printf '%s' "$path" | cut -d/ -f1-2)"
  url="https://github.com/$repo"

  # A pinned commit SHA (7–40 hex). With a `# vX.Y.Z` comment we verify it resolves to that
  # tag's commit; without a comment we can only report it (and nudge to add one).
  if printf '%s' "$pinref" | grep -qE '^[0-9a-f]{7,40}$'; then
    if [ -z "$tag" ]; then
      printf "PIN   %s  (commit SHA, no '# vX.Y.Z' comment — add one so it can be verified)\n" "$ref"
      pin=$((pin + 1))
      continue
    fi
    out="$("${LSREMOTE[@]}" "$url" "refs/tags/$tag" "refs/tags/$tag^{}" 2>/dev/null)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      printf 'SKIP  %s # %s  (could not reach %s)\n' "$ref" "$tag" "$url"
      skip=$((skip + 1))
    elif [ -z "$out" ]; then
      printf 'FAIL  %s # %s  (tag %s does not exist on %s)\n' "$ref" "$tag" "$tag" "$url"
      fail_lines+="  $ref # $tag"$'\n'
      fail=$((fail + 1))
    else
      # The commit a tag resolves to: for an annotated tag ls-remote prints both the tag-object
      # line and a peeled `<sha>\trefs/tags/<tag>^{}` line — GitHub checks out the PEELED commit,
      # so the pin must equal that, not the tag-object sha. A lightweight tag has one line (the
      # commit already). Compare as a prefix so a short (7+ hex) pin still matches its commit.
      commit_sha="$(printf '%s' "$out" | awk '{s = $1} $2 ~ /\^\{\}$/ {p = $1} END {print (p != "" ? p : s)}')"
      case "$commit_sha" in
        "$pinref"*)
          printf 'OK    %s # %s  (SHA matches tag %s)\n' "$ref" "$tag" "$tag"
          ok=$((ok + 1))
          ;;
        *)
          printf 'FAIL  %s # %s  (pinned SHA is not tag %s, which is %s)\n' "$ref" "$tag" "$tag" "$commit_sha"
          fail_lines+="  $ref # claims $tag but the SHA differs"$'\n'
          fail=$((fail + 1))
          ;;
      esac
    fi
    continue
  fi

  # A tag or branch ref (the legacy, non-SHA case): check that it resolves.
  out="$("${LSREMOTE[@]}" "$url" "refs/tags/$pinref" "refs/heads/$pinref" 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'SKIP  %s  (could not reach %s)\n' "$ref" "$url"
    skip=$((skip + 1))
  elif [ -n "$out" ]; then
    printf 'OK    %s  (tag/branch — resolves, but prefer a SHA pin)\n' "$ref"
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
  echo "Unresolved/invalid refs must be fixed — they will break CI at \"Prepare all required actions\" or mean a pin lies about its version:"
  printf '%s' "$fail_lines"
  echo "Pin a SHA that matches the claimed tag (resolve with: gh api repos/OWNER/REPO/commits/TAG --jq .sha), or a ref that actually exists."
  exit 1
fi
exit 0
