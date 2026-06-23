"""Shared helpers for the hooks' embedded-python heredocs.

Import from a heredoc by passing this directory as an argv:

    python3 - "$SELF_DIR/lib" <<'PYEOF'
    import sys
    sys.path.insert(0, sys.argv[1])
    from hook_helpers import git, is_test_path
    PYEOF

(Heredocs can't read piped stdin, so argv is already the convention — see CLAUDE.md.)
"""

import os
import re
import subprocess


def git(args):
    """Run git, returning stdout on success and '' on any failure."""
    try:
        r = subprocess.run(["git", *args], capture_output=True, text=True)
        return r.stdout if r.returncode == 0 else ""
    except OSError:
        return ""


def new_lines():
    """Yield (path, lineno, text) for every line Claude *newly introduced*: added lines in
    `git diff HEAD` plus every line of untracked files. Pre-existing committed lines are
    skipped, so committing or reverting clears whatever a Stop hook flagged. Shared by the
    debug-leftover and todo-leftover Stop hooks — keep their detection here in sync via this
    one walker (jscpd runs at threshold 0, so this must not be copy-pasted)."""
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


def collect_new_line_hits(keep, limit=15):
    """Walk new_lines(), keep those where keep(path, text) is truthy, dedup by (path, line),
    and return up to `limit` formatted "  path:line: text" strings — with a trailing
    "  ... and N more" when truncated, or [] when nothing matched. Shared by the
    debug-leftover and todo-leftover Stop hooks (jscpd runs at threshold 0)."""
    hits = []
    seen = set()
    for path, lineno, text in new_lines():
        if not keep(path, text):
            continue
        key = (path, lineno)
        if key in seen:
            continue
        seen.add(key)
        hits.append(f"  {path}:{lineno}: {text.strip()[:120]}")
    if not hits:
        return []
    shown = hits[:limit]
    extra = len(hits) - limit
    if extra > 0:
        shown.append(f"  ... and {extra} more")
    return shown


def is_test_path(path):
    """Test files/dirs. Keep in sync with reminder_is_test_path() in reminder-common.sh —
    same semantics, two languages."""
    base = os.path.basename(path)
    if re.match(r"test_.*\.py$", base):
        return True
    # _test.rb, .test.ts, _spec.rb, .spec.js, _test.go, ...
    if re.search(r"[._](?:test|spec)\.", base):
        return True
    return any(p in ("spec", "tests", "test", "__tests__") for p in path.split("/"))
