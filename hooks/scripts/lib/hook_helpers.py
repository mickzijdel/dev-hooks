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
