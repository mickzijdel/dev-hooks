#!/usr/bin/env python3
"""Apply bugs by hand, one at a time, and say which tests fail for each. Any stack.

    python3 hand_bug.py [--list FILE] [--timeout SECONDS] BUGS.json -- TEST COMMAND [ARG...]

BUGS.json: [{"id": "B1", "bug": "a cancelled order can be cancelled again",
             "file": "app/models/order.rb",
             "edits": [["raise AlreadyCancelled if cancelled?", ""]]}]

"file" is relative to the current folder. For each bug: every "find" text must occur exactly
once in the file; the edits are written, the test command runs once, the file is restored (also
when the run is interrupted or times out). The edit is temporary, so it is allowed where the
task may not change application code. --list appends each line of FILE (the scope list) to the
command. The command must pass before the first bug. Run it with retries off, and on the test
files that could catch the bug, not only the test under question: "which other test fails?" is
the point.
"""

import argparse
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ANSI = re.compile(r"\x1b\[[0-9;]*m")
# the named group is the failing test's name
FAILING = "|".join(  # noqa: FLY002 - one pattern per runner reads better as a list
    (
        # Vitest: "FAIL  |project| path > suite > test", and the same after "×" with a duration
        r"^\s*(?:FAIL|[×✗])\s+(?:\|[^|\n]+\|\s+)?(?P<vitest>\S+\.(?:test|spec)\.[cm]?[jt]sx? > .+?)(?:\s+\d+\s?ms)?$",
        r"^\s*●\s+(?P<jest>(?!Console\s*$).+)$",
        r"^(?:FAILED|ERROR) (?P<pytest>\S+::.+?)(?: - .*)?$",
        r"^(?:FAIL|ERROR): (?P<unittest>\w+ \(\S+\))",
        # not the verbose "Class#test_x = 0.01 s = ." line of a passing test
        r"\b(?P<minitest>[A-Z]\w*(?:::[A-Z]\w*)*#test_\w+[?!]?)(?![\w?!]| = [\d.]+ s = [.S])",
        r"^rspec (?P<rspec>\./\S+)",
    )
)


def run(command, log, timeout):
    """(exit code or None after a timeout, output). The output goes to a file, not a pipe: a
    process the command leaves behind would hold a pipe open after the kill."""
    with log.open("wb") as out:
        child = subprocess.Popen(
            command, stdout=out, stderr=subprocess.STDOUT, start_new_session=True
        )
        try:
            code = child.wait(timeout=timeout)
        except BaseException as stop:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
            if not isinstance(stop, subprocess.TimeoutExpired):
                raise
            code = None
    text = ANSI.sub("", log.read_bytes().decode(errors="replace"))
    log.write_text(text)
    return code, text


def mutated(text, bug):
    for find, replace in bug["edits"]:
        if text.count(find) != 1:
            sys.exit(
                f"{bug['id']}: {find!r} occurs {text.count(find)} times in {bug['file']}, not once"
            )
        text = text.replace(find, replace)
    return text


def main():
    parser = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0],
        usage="%(prog)s [--list FILE] [--timeout SECONDS] BUGS.json -- COMMAND...",
    )
    parser.add_argument("bugs")
    parser.add_argument(
        "--fail-pattern",
        default=FAILING,
        help="regex for one failing-test line of your runner's output (first group: the name)",
    )
    parser.add_argument(
        "--list", metavar="FILE", help="append each line of FILE to the command"
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=900,
        metavar="SECONDS",
        help="kill a test run that takes longer (a bug can make a suite hang); default 900",
    )
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or command[0].startswith("-"):
        parser.error("options go before BUGS.json; give the test command after --")
    if args.list:
        command += [row for row in Path(args.list).read_text().splitlines() if row]
    failing = re.compile(args.fail_pattern, re.MULTILINE)
    bugs = json.loads(Path(args.bugs).read_text())
    missing = sorted({b["file"] for b in bugs if not Path(b["file"]).is_file()})
    if missing:
        sys.exit(f"no such file (paths are relative to the current folder): {missing}")
    # bytes, so that line endings come back as they were
    originals = {b["file"]: Path(b["file"]).read_bytes() for b in bugs}
    # every edit is checked before the first run
    changed = [(b, mutated(originals[b["file"]].decode(), b)) for b in bugs]
    logs = Path(tempfile.mkdtemp(prefix="hand_bug-"))
    last = 0

    def write(file, data):
        """Every write gets a later whole second than the one before: bytecode caches (Python,
        Bootsnap) key on whole-second mtime and size, and build tools rebuild what is older
        than its source. So a restored file is newer than it was, on purpose."""
        nonlocal last
        Path(file).write_bytes(data)
        last = max(int(time.time()), last) + 1
        os.utime(file, (last, last))

    def stop(*_):
        raise KeyboardInterrupt

    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, stop)
    code, _ = run(command, logs / "baseline.log", args.timeout)
    if code != 0:
        why = "times out" if code is None else f"fails (exit {code})"
        sys.exit(f"the command {why} before any bug is applied: {logs}/baseline.log")
    print(f"baseline passes; logs in {logs}")
    for bug, text in changed:
        file = bug["file"]
        try:
            write(file, text.encode())
            code, out = run(command, logs / f"{bug['id']}.log", args.timeout)
        finally:
            write(file, originals[file])
        print(f"\n{bug['id']}: {bug['bug']}  ({file})")
        for find, replace in bug["edits"]:
            print(f"  - {find}\n  + {replace}")
        names = sorted(
            {
                next((g for g in m.groups() if g), m.group(0)).strip()
                for m in failing.finditer(out)
            }
        )
        if code == 0:
            print("  NO TEST FAILS")
        elif code is None:
            print(
                f"  TIMED OUT after {args.timeout:g} s (killed): read {logs}/{bug['id']}.log"
            )
        else:
            print(f"  exit {code}; failing ({len(names)}):")
            for name in names or [f"(no line matched; read {logs}/{bug['id']}.log)"]:
                print(f"    {name}")


if __name__ == "__main__":
    main()
