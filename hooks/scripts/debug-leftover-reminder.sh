#!/bin/bash
# Stop hook: flag debug statements Claude *newly introduced* this session (console.log,
# debugger, binding.pry, breakpoint(), pdb, Ruby `p`, ...) so they get stripped before
# finishing. Advisory — feeds the findings back via exit 2; never edits or hard-blocks.
#
# Only NEW lines are considered: added lines in `git diff HEAD` plus the full contents of
# untracked files. Pre-existing debug lines (already committed, unchanged) are ignored, so
# committing or removing the lines clears the nudge. Test files/dirs are excluded.
#
# Fires at most once per session: its own sentinel string, once emitted, lands in the
# transcript, and finding it there on a later Stop suppresses a re-fire (no Stop loop).
#
# Opt out per repo/user with DEV_HOOKS_DEBUG_LEFTOVER=false (in .claude settings "env").

case "${DEV_HOOKS_DEBUG_LEFTOVER:-}" in
  false | 0 | no | off) exit 0 ;;
esac

# Must be a git repo (diff-based detection needs one).
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

SENTINEL="[debug-leftover] new debug statements detected this session"

# Already nudged this session? Stay silent (prevents a Stop loop).
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  grep -qF "$SENTINEL" "$TRANSCRIPT" 2>/dev/null && exit 0
fi

FINDINGS=$(
  python3 - <<'PYEOF'
import os
import re
import subprocess

JS_EXT = {".js", ".ts", ".jsx", ".tsx", ".vue", ".mjs", ".cjs"}
PY_EXT = {".py"}
RB_EXT = {".rb", ".erb", ".rake"}

JS_PAT = re.compile(r"console\.(?:log|debug)\(|(?<![\w.])debugger\b")
PY_PAT = re.compile(r"\bbreakpoint\(\)|(?:^|[^\w.])i?pdb\.set_trace\(\)|^\s*import\s+i?pdb\b")
# Ruby debuggers, plus `p` used as a call: non-word/non-dot char before `p`, space/( after.
RB_PAT = re.compile(r"binding\.(?:pry|irb)|\bbyebug\b|(?<![\w.])debugger\b|(?:^|[^\w.])p[ (]")

PAT_FOR_EXT = {}
for e in JS_EXT:
    PAT_FOR_EXT[e] = JS_PAT
for e in PY_EXT:
    PAT_FOR_EXT[e] = PY_PAT
for e in RB_EXT:
    PAT_FOR_EXT[e] = RB_PAT


# jscpd:ignore-start - small git/test-path helpers intentionally shared with missing-test
def git(args):
    try:
        r = subprocess.run(["git", *args], capture_output=True, text=True)
        return r.stdout if r.returncode == 0 else ""
    except OSError:
        return ""


def is_test_path(path):
    base = os.path.basename(path)
    if re.search(r"(?:_spec\.rb|_test\.rb)$", base):
        return True
    if re.search(r"^test_.*\.py$|_test\.py$", base):
        return True
    if re.search(r"\.(?:test|spec)\.", base):
        return True
    parts = path.split("/")
    return any(p in ("spec", "tests", "test", "__tests__") for p in parts)
# jscpd:ignore-end


def candidate_lines():
    """Yield (path, lineno, text) for every newly-introduced line."""
    # Tracked edits vs HEAD (only when HEAD exists).
    if git(["rev-parse", "--verify", "HEAD"]).strip():
        cur, new_ln = None, None
        for line in git(["diff", "HEAD", "--no-color", "--unified=0"]).splitlines():
            if line.startswith("+++ "):
                p = line[4:]
                cur = p[2:] if p.startswith("b/") else p
            elif line.startswith("@@"):
                m = re.search(r"\+(\d+)", line)
                new_ln = int(m.group(1)) if m else None
            elif line.startswith("+") and not line.startswith("+++"):
                if cur is not None and new_ln is not None:
                    yield cur, new_ln, line[1:]
                    new_ln += 1
    # Untracked files: every line is new.
    for f in git(["ls-files", "--others", "--exclude-standard"]).splitlines():
        if not f:
            continue
        try:
            with open(f, encoding="utf-8", errors="replace") as fh:
                for i, text in enumerate(fh, 1):
                    yield f, i, text.rstrip("\n")
        except OSError:
            pass


hits = []
seen = set()
for path, lineno, text in candidate_lines():
    ext = os.path.splitext(path)[1]
    pat = PAT_FOR_EXT.get(ext)
    if pat is None or is_test_path(path):
        continue
    if pat.search(text):
        key = (path, lineno)
        if key in seen:
            continue
        seen.add(key)
        hits.append(f"  {path}:{lineno}: {text.strip()[:120]}")

if hits:
    extra = len(hits) - 15
    shown = hits[:15]
    if extra > 0:
        shown.append(f"  ... and {extra} more")
    print("\n".join(shown))
PYEOF
)

[ -z "$FINDINGS" ] && exit 0

MSG="${SENTINEL}. You introduced these debug statements this session — remove them before finishing (or, if one is intentional, keep it and ignore this):"$'\n'"$FINDINGS"

jq -cn --arg msg "$MSG" '{continue: false, hookSpecificOutput: {hookEventName: "Stop", additionalContext: $msg}}'
exit 2
