"""Shared helpers for the hooks' embedded-python heredocs.

Import from a heredoc by passing this directory as an argv:

    python3 - "$SELF_DIR/lib" <<'PYEOF'
    import sys
    sys.path.insert(0, sys.argv[1])
    from hook_helpers import git, is_test_path
    PYEOF

(Heredocs can't read piped stdin, so argv is already the convention — see CLAUDE.md.)
"""

import json
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


# ── Script-library helpers ──────────────────────────────────────────────────────────
# The marker a saved script carries so the SessionStart index can describe it, e.g.
#   # short-description: Fetch a PR diff by number.
# Matches "# short-description: …" (optional space after #). The shebang line "#!…" never
# matches, so it's safe to scan from line 1. Mirrored by the script-library skill's standard.
SHORT_DESC_RE = re.compile(r"#\s*short-description:\s*(.+)", re.IGNORECASE)


# Don't recurse below this many levels under a root — a scripts repo is organised a couple
# of levels deep; a deeper walk only risks scanning an accidental large tree.
_SCAN_MAX_DEPTH = 4


def _script_description(full):
    """If `full` is an executable file whose first bytes are a shebang, return its
    `# short-description:` text (or "" when it has none); return None when it isn't a script.
    Matches the dev-env "extensionless CLI = shebang on line 1" rule, so binaries and data
    files are skipped."""
    if not os.path.isfile(full) or not os.access(full, os.X_OK):
        return None
    try:
        with open(full, "rb") as fh:
            head = fh.read(4096)
    except OSError:
        return None
    if not head.startswith(b"#!"):
        return None
    for line in head.decode("utf-8", errors="replace").splitlines()[:20]:
        m = SHORT_DESC_RE.match(line.strip())
        if m:
            return m.group(1).strip()
    return ""


def scan_script_dirs(roots):
    """Inventory one or more library roots — each scanned recursively into subdirectories —
    for the SessionStart index. `roots` is an iterable of directory paths (a script repo can be
    organised into subdirs like `git/` or `images/`). Returns (described, undescribed):
    `described` is a sorted list of (abspath, short_description) and `undescribed` a sorted list
    of abspaths, for every executable shebang script found. Deduped across roots by abspath;
    hidden dirs (`.git`, …) are skipped and the walk is depth-limited."""
    described, undescribed, seen = [], [], set()
    for root in roots:
        root = os.path.abspath(os.path.expanduser(root))
        if not os.path.isdir(root):
            continue
        base_depth = root.rstrip(os.sep).count(os.sep)
        for dirpath, dirnames, filenames in os.walk(root):
            # Prune hidden dirs (.git, …) and stop descending past the depth cap.
            if dirpath.count(os.sep) - base_depth >= _SCAN_MAX_DEPTH:
                dirnames[:] = []
            dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
            for name in sorted(filenames):
                if name.startswith("."):
                    continue
                full = os.path.abspath(os.path.join(dirpath, name))
                if full in seen:
                    continue
                desc = _script_description(full)
                if desc is None:
                    continue
                seen.add(full)
                (described if desc else undescribed).append(
                    (full, desc) if desc else full
                )
    described.sort()
    undescribed.sort()
    return described, undescribed


def authored_scripts(transcript_path, exclude_dirs=()):
    """Scan a session transcript for *ephemeral* scripts Claude wrote this session — Write
    tool_use blocks whose content starts with a shebang (`#!`). Returns a deduped,
    order-preserving list of file_paths. Paths under any of `exclude_dirs` are skipped: pass
    the saved-script library (already kept) and the project working dir (committed work, not a
    throwaway), so only the genuine one-offs (scratchpad, /tmp, …) remain — the ones worth
    nudging into the library. Used by the save-script-reminder Stop hook."""
    prefixes = [
        os.path.abspath(os.path.expanduser(d)) + os.sep for d in exclude_dirs if d
    ]
    found, seen = [], set()
    try:
        with open(transcript_path, encoding="utf-8") as f:
            lines = list(f)
    except OSError:
        return found
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        msg = rec.get("message", rec)
        content = msg.get("content") if isinstance(msg, dict) else None
        for block in content if isinstance(content, list) else []:
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue
            if block.get("name") != "Write":
                continue
            inp = block.get("input") or {}
            path, body = inp.get("file_path"), inp.get("content")
            if not isinstance(path, str) or not isinstance(body, str):
                continue
            if not body.startswith("#!") or path in seen:
                continue
            full = os.path.abspath(os.path.expanduser(path))
            if any(full.startswith(p) for p in prefixes):
                continue
            seen.add(path)
            found.append(path)
    return found
