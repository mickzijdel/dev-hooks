#!/bin/bash
# Stop hook: when Claude adds a NEW source file this session with no matching test file,
# nudge it to add one (TDD / "Always Works"). Advisory — feeds back via exit 2; never edits.
#
# Only newly-added files are considered (untracked `??` or staged-added `A`); modifications
# to existing files are ignored. Test files, a few low-value-to-test files (package
# barrels, type defs, config, migrations, __init__/conftest), and vendored/generated code
# are excluded to limit noise. Vendored/generated dirs come from the repo's own .jscpd.json
# ignorePattern at run time (falling back to a built-in default when absent); minified
# files (*.min.js etc.) are always skipped.
#
# Fires at most once per session via its own transcript sentinel (mirrors review-reminder),
# so there is no Stop loop.
#
# Opt out per repo/user with DEV_HOOKS_MISSING_TEST=false (in .claude settings "env").

case "${DEV_HOOKS_MISSING_TEST:-}" in
  false | 0 | no | off) exit 0 ;;
esac

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

SENTINEL="[missing-test] new source files without tests this session"

if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  grep -qF "$SENTINEL" "$TRANSCRIPT" 2>/dev/null && exit 0
fi

FINDINGS=$(
  python3 - <<'PYEOF'
import json
import os
import re
import subprocess

PY_EXT = {".py"}
RB_EXT = {".rb"}
JS_EXT = {".js", ".ts", ".jsx", ".tsx", ".mjs", ".cjs"}
TESTABLE = PY_EXT | RB_EXT | JS_EXT


# jscpd:ignore-start - small git/test-path helpers intentionally shared with debug-leftover
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


def is_low_value(path):
    base = os.path.basename(path)
    if base in ("__init__.py", "conftest.py"):
        return True
    if base.endswith(".d.ts"):
        return True
    if re.search(r"\.config\.[a-z]+$", base):
        return True
    if base in ("index.js", "index.ts"):
        return True
    parts = path.split("/")
    return "migrate" in parts or "migrations" in parts or "db/migrate" in path


# Vendored/generated directories. Kept in sync with the .jscpd.json template's
# ignorePattern via tests/test_dev_env_templates.py; the runtime read below prefers the
# repo's own .jscpd.json and falls back to this when the repo has none.
DEFAULT_VENDOR_DIRS = {
    "__pycache__",
    ".venv",
    "node_modules",
    "vendor",
    "dist",
    "build",
    "app/assets/builds",
}


def read_jscpd_dirs():
    toplevel = git(["rev-parse", "--show-toplevel"]).strip()
    if not toplevel:
        return None
    try:
        with open(os.path.join(toplevel, ".jscpd.json")) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    dirs = set()
    for pat in data.get("ignorePattern", []):
        m = re.match(r"^\*\*/(.+)/\*\*$", pat)
        if m:
            dirs.add(m.group(1))
    return dirs or None


def is_vendored(path, dirs):
    padded = "/" + path + "/"
    if any(("/" + d + "/") in padded for d in dirs):
        return True
    return bool(re.search(r"\.min\.[A-Za-z]+$", os.path.basename(path)))


def has_test(stem, ext, basenames):
    cands = set()
    if ext in PY_EXT:
        cands |= {f"test_{stem}.py", f"{stem}_test.py"}
    elif ext in RB_EXT:
        cands |= {f"{stem}_spec.rb", f"{stem}_test.rb"}
    elif ext in JS_EXT:
        for e in ("js", "ts", "jsx", "tsx", "mjs", "cjs"):
            cands |= {f"{stem}.test.{e}", f"{stem}.spec.{e}"}
    return any(c in basenames for c in cands)


# All known files (tracked + untracked) -> set of basenames, to look up matching tests.
all_files = git(["ls-files"]).splitlines()
all_files += git(["ls-files", "--others", "--exclude-standard"]).splitlines()
basenames = {os.path.basename(f) for f in all_files if f}

# Newly-added source files from porcelain status.
vendor_dirs = read_jscpd_dirs() or DEFAULT_VENDOR_DIRS
missing = []
for line in git(["status", "--porcelain"]).splitlines():
    if not line:
        continue
    status, path = line[:2], line[3:]
    # Untracked new file, or staged addition.
    if status != "??" and status[0] != "A":
        continue
    # Renames show "old -> new"; take the new path.
    if " -> " in path:
        path = path.split(" -> ", 1)[1]
    ext = os.path.splitext(path)[1]
    if ext not in TESTABLE or is_test_path(path) or is_low_value(path):
        continue
    if is_vendored(path, vendor_dirs):
        continue
    stem = os.path.splitext(os.path.basename(path))[0]
    if not has_test(stem, ext, basenames):
        missing.append(f"  {path}")

if missing:
    print("\n".join(missing[:15]))
PYEOF
)

[ -z "$FINDINGS" ] && exit 0

MSG="${SENTINEL}. You added these source files this session but I found no matching test for them — add tests before finishing (TDD / \"Always Works\"). If a file genuinely doesn't warrant a test, say so and move on:"$'\n'"$FINDINGS"

jq -cn --arg msg "$MSG" '{continue: false, hookSpecificOutput: {hookEventName: "Stop", additionalContext: $msg}}'
exit 2
