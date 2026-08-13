#!/bin/bash
# bet: model adds new source files without a matching test
# sunset: model reliably adds a test alongside new source unprompted
# Stop hook: when Claude adds a NEW source file this session with no matching test file,
# nudge it to add one (TDD / "Always Works"). Advisory — feeds back via exit 2; never edits.
#
# Only newly-added files are considered — untracked `??`, staged-added `A`, and files added
# by commits made since the session started (the transcript's first-line timestamp).
# That last source is what makes the hook work at all under the commit-as-you-go workflow:
# with a clean tree at Stop time, porcelain status alone reports nothing. Files added and
# then deleted again within the session don't count. Modifications
# to existing files are ignored. Test files, a few low-value-to-test files (package
# barrels, type defs, config, migrations, __init__/conftest), and vendored/generated code
# are excluded to limit noise. Vendored/generated dirs come from the repo's own .jscpd.json
# `ignore` globs at run time (falling back to a built-in default when absent); minified
# files (*.min.js etc.) are always skipped.
#
# Fires at most once per session via its own transcript sentinel (mirrors review-reminder),
# so there is no Stop loop.
#
# Opt out per repo/user with DEV_HOOKS_MISSING_TEST=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
reminder_opt_out DEV_HOOKS_MISSING_TEST

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

SENTINEL="[missing-test] new source files without tests this session"

# Sets INPUT/TRANSCRIPT; exits 0 if the sentinel is already in the transcript.
reminder_stop_init "$SENTINEL"

reminder_session_since
SINCE=$REPLY

FINDINGS=$(
  python3 - "$SELF_DIR/lib" "$SINCE" <<'PYEOF'
import json
import os
import re
import sys

sys.dont_write_bytecode = True  # no __pycache__ in the plugin's lib dir
sys.path.insert(0, sys.argv[1])
from hook_helpers import git, is_test_path

PY_EXT = {".py"}
RB_EXT = {".rb"}
JS_EXT = {".js", ".ts", ".jsx", ".tsx", ".mjs", ".cjs"}
TESTABLE = PY_EXT | RB_EXT | JS_EXT


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
# `ignore` globs via tests/test_dev_env_templates.py; the runtime read below prefers the
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


# git reports paths relative to the repo root, which isn't necessarily the hook's cwd.
TOPLEVEL = git(["rev-parse", "--show-toplevel"]).strip()


def read_jscpd_dirs():
    if not TOPLEVEL:
        return None
    try:
        with open(os.path.join(TOPLEVEL, ".jscpd.json")) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    dirs = set()
    # v12 uses `ignore` (the key jscpd v5 honors for paths); `ignorePattern` is the
    # pre-v12 key, still read so not-yet-upgraded repos keep their exclusions.
    for pat in data.get("ignore", []) + data.get("ignorePattern", []):
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


def added_paths():
    """Every path this session newly added: uncommitted (porcelain) plus, when the session
    start is known, files added by commits made since. Deleted-again paths drop out via the
    exists() check, so a scratch file created and removed within the session stays quiet."""
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
        yield path
    since = sys.argv[2] if len(sys.argv) > 2 else ""
    if not since:
        return
    yield from git(
        ["log", f"--since={since}", "--diff-filter=A", "--name-only", "--format="]
    ).splitlines()


# Newly-added source files this session.
vendor_dirs = read_jscpd_dirs() or DEFAULT_VENDOR_DIRS
missing = []
seen = set()
for path in added_paths():
    if not path or path in seen:
        continue
    seen.add(path)
    if not os.path.exists(os.path.join(TOPLEVEL, path) if TOPLEVEL else path):
        continue
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

reminder_emit_stop "$MSG"
