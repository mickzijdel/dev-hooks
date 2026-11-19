#!/usr/bin/env python3
"""Find tests that cannot fail or never run: no assertion, tautologies, mock- or snapshot-only
assertions, focused or skipped tests, fixed sleeps. TypeScript/JavaScript, Ruby, Python.

    python3 test_smells.py [DIR ...]

Heuristic: blocks are found by brace matching (JS/TS), `end` at the same indent (Ruby) and
indentation (Python). Every hit is a candidate to read, not a verdict.
"""

import re
import sys
from collections import defaultdict
from pathlib import Path

SKIP_DIRS = {
    "node_modules",
    "vendor",
    ".git",
    "dist",
    "build",
    "coverage",
    ".venv",
    "tmp",
    ".worktrees",
}
TEST_FILE = re.compile(
    r"(_test\.rb|_spec\.rb|^test_.*\.py|_test\.py|\.(test|spec)\.[cm]?[jt]sx?)$"
)

ASSERT = {
    "js": r"\bexpect\w*\s*[.(]|\bdone\s*\(\s*\)|\bassert\w*\s*[.(]|\.should\b|\bt\.(is|true|false|deepEqual|throws)\b",
    "rb": r"\b(assert\w*|refute\w*|expect|is_expected|must_\w+|wont_\w+|should)\b",
    "py": r"\bassert\b|\.assert\w+\(|pytest\.(raises|warns|fail)\b",
}
MOCK = {
    "js": r"\.(toHaveBeenCalled\w*|toBeCalled\w*|toHaveBeenNthCalledWith|toHaveReturned\w*)\b",
    "rb": r"\b(assert_called\w*|assert_received|expect\(.+?\)\.to(_not)? (have_)?receive\w*|\.verify)\b",
    "py": r"\.assert_(not_)?(called|any_call|has_calls)\w*\b",
}
SNAPSHOT = {
    "js": r"\.(toMatchSnapshot|toMatchInlineSnapshot|toMatchFileSnapshot)\b",
    "rb": r"\bmatch_snapshot\b",
    "py": r"\bsnapshot\b",
}
TAUTOLOGY = {
    "js": r"expect\(\s*(true|false|null|undefined|\d+|(['\"])[^'\"]*\2)\s*\)\.(toBe|toEqual|toStrictEqual)\(|expect\((\w+)\)\.(toBe|toEqual)\(\4\)",
    "rb": r"^\s*assert\s*\(?\s*true\s*\)?\s*$|^\s*refute\s*\(?\s*false\s*\)?\s*$|assert_equal\s*\(?\s*(\S+?),\s*\1\s*\)?\s*$",
    "py": r"^\s*assert\s+(True|1)\s*$|^\s*assert\s+(\w+)\s*==\s*\2\s*$",
}
SLEEP = {
    "js": r"\bwaitForTimeout\(|new Promise\(\s*\(?\w*\)?\s*=>\s*setTimeout\(|\bsleep\(\s*\d",
    "rb": r"\bsleep\s*\(?\s*\d",
    "py": r"\btime\.sleep\(|\bsleep\(\s*\d",
}
# per test (read on the test's header line, or its body for Ruby/Python skips)
FOCUSED = {
    "js": r"^\s*(it|test)\.only\s*\(|^\s*fit\s*\(",
    "rb": r"^\s*fit\b|\bfocus:\s*true",
    "py": r"(?!)",
}
SKIPPED = {
    "js": r"^\s*(it|test)\.(skip|todo)\s*\(|^\s*x(it|test)\s*\(",
    "rb": r"^\s*(skip|pending)(\s*$|\s*\(|\s+[\"'])|^\s*xit\b",
    "py": r"@pytest\.mark\.(skip|xfail)\b|\bpytest\.skip\(",
}
# per file: groups, and Minitest's `focus` on the line before a test
FILE_FOCUSED = {
    "js": r"^\s*(describe|context|suite)\.only\s*\(|^\s*fdescribe\s*\(",
    "rb": r"^\s*focus\s*$|^\s*f(describe|context)\b",
    "py": r"(?!)",
}
FILE_SKIPPED = {
    "js": r"^\s*(describe|context|suite)\.skip\s*\(|^\s*xdescribe\s*\(",
    "rb": r"^\s*x(describe|context)\b",
    "py": r"^\s*pytestmark\s*=.*\bskip",
}

JS_TEST = re.compile(
    r"(?m)^\s*(?:[fx]?it|x?test)(?:\.(?:only|skip|todo|concurrent|fails))?(?:\.each\s*\([^)]*\)\s*)?\s*\(\s*(['\"`])(.*?)\1"
)
RB_TEST = re.compile(
    r"^(\s*)(?:test\s+(['\"])(.+?)\2.*\bdo\b|def\s+(test_\w+)|[fx]?it\s+(['\"])(.+?)\5.*\bdo\b)"
)
PY_TEST = re.compile(r"^(\s*)(?:async\s+)?def\s+(test_\w+)\s*\(")
JS_HELPER = re.compile(
    r"(?:function\s+(\w+)\s*[<(]|(?:const|let)\s+(\w+)\s*(?::[^=]+)?=\s*(?:async\s*)?(?:\(|<|\w+\s*=>|function\b))"
)
RB_HELPER = re.compile(r"^\s*def\s+((?!test_)\w+[?!]?)")
PY_HELPER = re.compile(r"^\s*def\s+((?!test_)\w+)\s*\(")


def lang(path):
    return {".rb": "rb", ".py": "py"}.get(path.suffix, "js")


def js_body(src, start):
    """The text of the first {...} block (or arrow expression) after start, braces matched."""
    i = src.find("=>", start)
    j = src.find("function", start)
    k = min(x for x in (i, j, len(src)) if x >= 0)
    open_ = src.find("{", k)
    if open_ < 0 or not re.fullmatch(r"(?:=>|async|function\b[^{]*|\s)*", src[k:open_]):
        end = src.find("\n", k)  # expression body: `() => expect(x).toBe(1)`
        return src[k : end if end > 0 else len(src)]
    depth, n, quote = 0, open_, None
    templates = []  # brace depth at each open `${` inside a template literal
    while n < len(src):
        c = src[n]
        if quote:
            if c == "\\":
                n += 1
            elif quote == "`" and src.startswith("${", n):
                templates.append(depth)
                depth, quote = depth + 1, None
                n += 1
            elif c == quote:
                quote = None
        elif c in "'\"`" and not (c == "'" and n and src[n - 1].isalnum()):
            quote = c  # an apostrophe after a letter is JSX text (Don't), not a string
        elif src.startswith("/*", n):
            n = src.find("*/", n + 2)
            if n < 0:
                break
            n += 1
        elif src.startswith("//", n):
            n = src.find("\n", n)
            if n < 0:
                break
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if templates and depth == templates[-1]:
                templates.pop()
                quote = "`"
            elif depth == 0:
                return src[open_ : n + 1]
        n += 1
    return src[open_:]


def blocks(path, src):
    """Yield (line, name, body) per test."""
    lines = src.splitlines()
    if lang(path) == "js":
        for m in JS_TEST.finditer(src):
            yield (
                src.count("\n", 0, m.start()) + 1,
                m.group(2),
                m.group(0) + js_body(src, m.end()),
            )
        return
    for idx, line in enumerate(lines):
        if lang(path) == "rb":
            m = RB_TEST.match(line)
            if not m:
                continue
            name = m.group(3) or m.group(4) or m.group(6)
            if re.search(r"\bdef\s+test_\w+(\(.*?\))?\s*=", line):  # endless def
                yield idx + 1, name, line
                continue
            end = next(
                (
                    j
                    for j in range(idx + 1, len(lines))
                    if re.match(rf"^{m.group(1)}end\b", lines[j])
                ),
                len(lines),
            )
            yield idx + 1, name, "\n".join(lines[idx : end + 1])
        else:
            m = PY_TEST.match(line)
            if not m:
                continue
            ind = len(m.group(1))
            # a signature can span lines: the body starts after the line that ends in ":"
            sig = next(
                (
                    j
                    for j in range(idx, len(lines))
                    if re.search(r":\s*(#.*)?$", lines[j])
                ),
                idx,
            )
            end = next(
                (
                    j
                    for j in range(sig + 1, len(lines))
                    if lines[j].strip()
                    and len(lines[j]) - len(lines[j].lstrip()) <= ind
                ),
                len(lines),
            )
            top = idx
            while top > 0 and lines[top - 1].strip().startswith("@"):
                top -= 1
            # decorators go last: the checks read the body as every line after the first
            yield idx + 1, m.group(2), "\n".join(lines[idx:end] + lines[top:idx])


def block_end(lines, i, lg):
    """Index of the last line of the Ruby or Python block that starts at line i."""
    ind = len(lines[i]) - len(lines[i].lstrip())
    for j in range(i + 1, len(lines)):
        line = lines[j]
        if lg == "rb" and re.match(rf"^{' ' * ind}end\b", line):
            return j
        # a line at the def's indent ends it, unless it closes a multi-line signature
        if (
            lg == "py"
            and line.strip()
            and len(line) - len(line.lstrip()) <= ind
            and not re.match(r"\s*\)", line)
        ):
            return j - 1
    return len(lines) - 1


def asserting_helpers(files):
    """Names of helper functions in test code whose own body asserts: a call to one counts."""
    names = set()
    for path, src in files:
        lg = lang(path)
        lines = src.splitlines()
        pat = {"js": JS_HELPER, "rb": RB_HELPER, "py": PY_HELPER}[lg]
        offset = 0
        for i, line in enumerate(lines):
            m = pat.search(line)
            if m:
                name = next(g for g in m.groups() if g)
                if lg == "js":
                    body = js_body(src, offset + m.end())
                elif lg == "rb" and re.search(r"\bdef\s+\w+[?!]?(\(.*?\))?\s*=", line):
                    body = line  # endless def
                else:
                    body = "\n".join(lines[i + 1 : block_end(lines, i, lg) + 1])
                if re.search(ASSERT[lg], body):
                    names.add(name)
            offset += len(line) + 1
    return names


def scan(roots):
    files = []
    for root in roots:
        for p in Path(root).rglob("*"):
            if (
                p.is_file()
                and TEST_FILE.search(p.name)
                and not SKIP_DIRS & set(p.relative_to(root).parts)
            ):
                files.append((p, p.read_text(errors="replace")))
    support = [(p, s) for p, s in files]
    # helpers in support files (test_helper.rb, conftest.py, test/utils.ts)
    for root in roots:
        for p in Path(root).rglob("*"):
            rel = p.relative_to(root)
            if (
                p.is_file()
                and p.suffix in {".rb", ".py", ".ts", ".tsx", ".js"}
                and not SKIP_DIRS & set(rel.parts)
                and re.search(
                    r"/(test|tests|spec|__tests__)/",
                    f"/{Path(root).resolve().name}/{rel}",
                )
                and not TEST_FILE.search(p.name)
            ):
                support.append((p, p.read_text(errors="replace")))
    helpers = asserting_helpers(support)
    helper_call = (
        re.compile(r"\b(" + "|".join(map(re.escape, sorted(helpers))) + r")\b")
        if helpers
        else None
    )

    found = defaultdict(list)
    total = 0
    for path, src in files:
        lg = lang(path)
        for n, text in enumerate(src.splitlines(), 1):
            if re.search(FILE_FOCUSED[lg], text):
                found["focused (.only): the rest of the file never runs"].append(
                    f"{path}:{n}  {text.strip()}"
                )
            if re.search(FILE_SKIPPED[lg], text):
                found["skipped or todo"].append(f"{path}:{n}  {text.strip()}")
        for line, name, body in blocks(path, src):
            total += 1
            where = f"{path}:{line}  {name}"
            code = (
                "\n".join(
                    body.splitlines()[1:] or [body.split("=", 1)[-1]]
                )  # endless def
                if lg != "js"
                else body[body.find("(") :]
            )
            if re.search(
                FOCUSED[lg], body.splitlines()[0] if lg == "js" else body, re.MULTILINE
            ):
                found["focused (.only): the rest of the file never runs"].append(where)
            if re.search(SKIPPED[lg], body, re.MULTILINE):
                found["skipped or todo"].append(where)
                continue
            asserts = re.findall(ASSERT[lg], code, re.MULTILINE)
            helped = bool(helper_call and helper_call.search(code))
            if not asserts and not helped:
                found["no assertion"].append(where)
                continue
            if re.search(TAUTOLOGY[lg], code, re.MULTILINE):
                found["tautology (always passes)"].append(where)
            n_assert = len(re.findall(ASSERT[lg], code, re.MULTILINE))
            n_mock = len(re.findall(MOCK[lg], code, re.MULTILINE))
            n_snap = len(re.findall(SNAPSHOT[lg], code, re.MULTILINE))
            if n_mock and n_mock >= n_assert and not helped:
                found["asserts only on mocks"].append(where)
            if n_snap and n_snap >= n_assert and not helped:
                found["snapshot only"].append(where)
            if re.search(SLEEP[lg], code, re.MULTILINE):
                found["fixed sleep"].append(where)
    return total, found


def main():
    roots = sys.argv[1:] or ["."]
    total, found = scan(roots)
    print(f"tests: {total}")
    for smell in sorted(found, key=lambda s: -len(found[s])):
        print(f"\n{smell}: {len(found[smell])}")
        for w in found[smell]:
            print(f"  {w}")


if __name__ == "__main__":
    main()
