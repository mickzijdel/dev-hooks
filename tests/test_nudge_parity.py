"""The mod's Stop-nudge remedies (hooks/nudge-outcomes.ts) mirror what the shell hooks
count as done. A drifted copy doesn't error: it silently records acted-on nudges as
ignored. These pin each mirrored value to its source."""

import re
import sys

from conftest import DEV_HOOKS, HOOKS

NUDGES_TS = (DEV_HOOKS / "hooks" / "nudge-outcomes.ts").read_text()


def _ts_regex_source(name):
    return re.search(rf"export const {name} = /(.+)/\n", NUDGES_TS).group(1)


def test_review_needles_match_review_reminder():
    sh = (HOOKS / "review-reminder.sh").read_text()
    args = re.search(r'reminder_transcript_invoked "" (.+)', sh).group(1).split()
    names = [a for a in args if not a.startswith("agent:")]
    jobs = [a[len("agent:") :] for a in args if a.startswith("agent:")]
    ts = re.search(r"export const REVIEW_NEEDLES = \[(.+)\]", NUDGES_TS).group(1)
    assert re.findall(r"'([^']+)'", ts) == names
    assert jobs == ["review"]
    assert "invokedSince(ev.facts, n.at, REVIEW_NEEDLES, 'review')" in NUDGES_TS


def test_memory_dir_rule_matches_hook_helpers():
    sys.path.insert(0, str(HOOKS / "lib"))
    sys.dont_write_bytecode = True
    from hook_helpers import MEMORY_DIR_RE

    assert (
        _ts_regex_source("MEMORY_DIR_RE").replace("\\/", "/") == MEMORY_DIR_RE.pattern
    )


def test_compress_comments_needle_matches_its_hook():
    sh = (HOOKS / "compress-comments-reminder.sh").read_text()
    assert 'reminder_transcript_invoked "" compress-comments\n' in sh
    assert "invokedSince(ev.facts, n.at, ['compress-comments'])" in NUDGES_TS
