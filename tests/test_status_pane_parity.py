"""The session-status pane (hooks/status-pane.ts) reads end reports with the same label
patterns end-report-reminder checks for. A drifted copy doesn't error: the hook would
accept a report the pane can't read, and the pane would show "no end report"."""

import re

from conftest import DEV_HOOKS, HOOKS

PANE_TS = (DEV_HOOKS / "hooks" / "status-pane.ts").read_text()
HELPERS_PY = (HOOKS / "lib" / "hook_helpers.py").read_text()


def test_end_report_labels_match_the_hook():
    mirrored = dict(
        re.findall(
            r"^\s+(changed|yourMove): String\.raw`([^`]+)`,", PANE_TS, re.MULTILINE
        )
    )
    canon = dict(
        re.findall(r'^\s+"(Changed|Your move)": r"([^"]+)",', HELPERS_PY, re.MULTILINE)
    )
    assert mirrored == {"changed": canon["Changed"], "yourMove": canon["Your move"]}


def test_label_suffix_matches_the_hook():
    mirrored = re.search(
        r"^const TAIL = String\.raw`([^`]+)`", PANE_TS, re.MULTILINE
    ).group(1)
    canon = re.search(r'^\s+tail = r"([^"]+)"', HELPERS_PY, re.MULTILINE).group(1)
    assert mirrored == canon
