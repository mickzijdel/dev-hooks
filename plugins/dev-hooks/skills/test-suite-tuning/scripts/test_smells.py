#!/usr/bin/env python3
"""Find tests that cannot fail or never run: no assertion, tautologies, mock- or snapshot-only
assertions, focused or skipped tests, conditional skips, fixed sleeps. TypeScript/JavaScript,
Ruby, Python.

    python3 test_smells.py [--only REGEX | --list FILE] [--all] [ROOT ...]

Heuristic: JS/TS is read with strings, comments and regex literals blanked and brackets
matched; Ruby blocks end at `end` on the same indent, Python blocks by indentation. Every hit
is a candidate to read, not a verdict.
"""

import argparse
import os
import re
import sys
from bisect import bisect_left
from collections import defaultdict
from functools import cache
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
TEST_DIRS = {"test", "tests", "spec", "__tests__"}
TEST_FILE = re.compile(
    r"(_test\.rb|_spec\.rb|^test_.*\.py|_test\.py|\.(test|spec)\.[cm]?[jt]sx?)$"
)

ASSERT = {
    "js": r"\bexpect\w*\s*[.(<]|\bdone\s*\(\s*\)|\bassert\w*\s*[.(<]|\.should\b|\bt\.(is|true|false|deepEqual|throws)\b",
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
NUM = r"\d[\d_]*(?:\.\d+)?"
# group 1 is the literal duration, in seconds
SLEEP = {
    "rb": re.compile(rf"\bsleep\s*\(?\s*({NUM})"),
    "py": re.compile(rf"\b(?:time\.sleep\(\s*|sleep\(\s*(?=\d))({NUM})?"),
}
# Ruby and Python, per test (read on the test's body)
FOCUSED = {"rb": r"^\s*fit\b|\bfocus:\s*true", "py": r"(?!)"}
SKIPPED = {
    "rb": r"^\s*(skip|pending)(\s*$|\s*\(|\s+[\"'])|^\s*xit\b",
    "py": r"@pytest\.mark\.(skip|xfail)\b|\bpytest\.skip\(|@(unittest\.)?skip\(",
}
# per file: groups, and Minitest's `focus` on the line before a test
FILE_FOCUSED = {
    "js": r"^\s*(describe|context|suite)(\.\w+)*\.only\b|^\s*fdescribe\s*\(",
    "rb": r"^\s*focus\s*$|^\s*f(describe|context)\b",
    "py": r"(?!)",
}
FILE_SKIPPED = {
    "js": r"^\s*(describe|context|suite)(\.\w+)*\.skip\b|^\s*xdescribe\s*\(",
    "rb": r"^\s*x(describe|context)\b",
    "py": r"^\s*pytestmark\s*=.*\bskip",
}
# per line: a skip that depends on a condition
COND_SKIPPED = {
    # the if or unless is outside the message's quotes
    "rb": r"""^\s*(skip|pending)\b(?:[^"'\n]|"[^"\n]*"|'[^'\n]*')*\s(if|unless)\s""",
    "py": r"@pytest\.mark\.skipif\b|\bpytest\.importorskip\(|@(unittest\.)?skip(If|Unless)\b",
}
SKIM = ("asserts only on mocks", "snapshot only")  # long lists that are mostly fine
SKIM_LIMIT = 25
FOCUS = "focused (.only): the rest of the file never runs"
SKIP = "skipped or todo"
COND_SKIP = "conditional skip: check the condition is not something the lane provides"

RB_TEST = re.compile(
    r"^(\s*)(?:test\s+(['\"])(.+?)\2.*\bdo\b|def\s+(test_\w+)|[fx]?it\s+(['\"])(.+?)\5.*\bdo\b)"
)
PY_TEST = re.compile(r"^(\s*)(?:async\s+)?def\s+(test_\w+)\s*\(")
RB_HELPER = re.compile(r"^\s*def\s+((?!test_)\w+[?!]?)")
PY_HELPER = re.compile(r"^\s*def\s+((?!test_)\w+)\s*\(")

JS_TOKEN = re.compile(
    r"(?<!:)//[^\n]*|/\*[\s\S]*?(?:\*/|\Z)"
    r"|\"(?:[^\"\\\n]|\\.)*\"|'(?:[^'\\\n]|\\.)*'|[`/(){}'\"]"
)
JS_TEMPLATE = re.compile(r"\\[\s\S]|`|\$\{")
JS_REGEX = re.compile(r"/(?:[^/\\\n\[]|\\.|\[(?:[^\]\\\n]|\\.)*\])+/\w*")
JS_TEST = re.compile(
    r"(?m)^[ \t]*([fx]?it|x?test)((?:\.(?:only|skip|todo|concurrent|sequential|fails"
    r"|fail|fixme|slow|each|for|skipIf|runIf))*)[ \t]*(?=[(`])"
)
PARAMETRISED = {"each", "for"}
CURRIED = PARAMETRISED | {"skipIf", "runIf"}  # it.each(table)("title", ...)
JS_GROUP_EACH = re.compile(
    r"(?m)^[ \t]*(?:describe|context|suite)(?:\.\w+)*\.(?:each|for)\b"
)
JS_COND_SKIP = re.compile(
    r"\b(?:describe|context|suite|it|test)(?:\.\w+)*\.(?:skipIf|runIf)\s*\("
    r"|\btest\.describe(?:\.\w+)*\.(?:skip|fixme)\s*\(|\.fixme\s*\("
    r"|\btest\.skip\s*\(\s*(?!['\"`])"
)
JS_FN = re.compile(r"=>|\bfunction\b")
JS_DEF = re.compile(
    r"\bfunction\b\s*\*?\s*(?P<decl>\w+)\s*(?:<[^()]*?>)?\s*\("
    r"|\b(?:const|let|var)\s+(?P<name>\w+)\s*(?::[^=\n]+)?=\s*(?:async\s+)?"
    r"(?:(?P<fn>function\b[^(]*\()|(?:<[^()=]*>\s*)?\(|(?P<arrow>\w+\s*=>))"
)
JS_IMPORT = re.compile(
    r"""(?m)^[ \t]*(import|export)\s+(?:type\s+)?([\w$\s,{}*]*?)\s*from\s*['"]([^'"\n]+)['"]"""
)
JS_CALL = re.compile(rf"(?<![.\w$])([A-Za-z_$][\w$]*)\s*\(\s*(?:({NUM})\s*[,)])?")
FAKE_TIMERS = re.compile(
    r"\buseFakeTimers\b|\b(?:advanceTimers|runAllTimers|runOnlyPendingTimers)\w*\("
    r"|\.clock\.(?:install|fastForward|runFor)\("
)
SET_TIMEOUT = re.compile(r"\bsetTimeout\s*\(")
PG_SLEEP = re.compile(rf"\bpg_sleep\(\s*({NUM})?")
JS_LOOP = re.compile(r"\b(?:while|for)\s*(?:await\s*)?\(|\bdo\s*\{")
LOOP_EXIT = re.compile(r"\b(?:break|return)\b")
# an imported file can hold helpers when it is test code: production code that sleeps or
# calls an `assert...` function is the code under test
TEST_CODE = re.compile(
    r"""\bexpect\w*\s*[.(<]|\b(?:vi|jest)\.\w+\(|\bexport\s*(?:\*|\{[^}]*\})\s*from\b"""
    r"""|['"](?:vitest|@jest/globals|@playwright/test|node:test|chai|sinon|cypress"""
    r"""|@testing-library/[\w-]+)['"]"""
)
JS_EXTS = ("", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs")
NOT_NEWLINE = re.compile(r"[^\n]+")
SPACE = re.compile(r"\s*")
STOP = re.compile(r"[(){};\n]")


@cache
def sleep_pattern(timers):
    """Sleeps as written in JS/TS; timers are the local names of timers/promises' setTimeout."""
    names = "|".join(sorted({"sleep", "delay", "wait", "setTimeout", *timers}))
    return re.compile(
        rf"(?P<timeout>\bwaitForTimeout\(\s*(?P<ms>{NUM})?)"
        r"|(?P<promise>\bnew\s+Promise\s*(?:<[^()\n]*>)?\s*\()"
        rf"|(?<![\w$])(?P<name>{names})\s*\(\s*"
        rf"(?:(?P<arg>{NUM})\s*[,)]|(?P<none>\(|\)|async\b|function\b))?"
    )


def lang(path):
    return {".rb": "rb", ".py": "py"}.get(Path(path).suffix, "js")


def millis(text, factor=1):
    return float(text.replace("_", "")) * factor if text else None


def longest(naps):
    return max((n for n in naps if n is not None), default=None)


def blank(text):
    return NOT_NEWLINE.sub(lambda m: " " * len(m.group()), text)


def regex_can_start(src, at):
    """Is the `/` at offset `at` the start of a regex literal (not a division or a JSX tag)?"""
    j = at - 1
    while j >= 0 and src[j] in " \t\r\n":
        j -= 1
    return j < 0 or src[j] in "(=,:[!&|?{;" or src.endswith(("return", "=>"), 0, j + 1)


def mask(src):
    """(src with string, comment and regex contents blanked, {opener offset: closer offset})
    for every `(`, `{` and template backtick. Offsets and line breaks stay the same."""
    out, last = [], 0
    pairs, parens, braces, templates = {}, [], [], []
    pos, text_from = 0, None  # text_from: where the template text being read starts

    def hide(a, b):
        nonlocal last
        out.append(src[last:a])
        out.append(blank(src[a:b]))
        last = b

    while pos < len(src):
        if text_from is not None:
            m = JS_TEMPLATE.search(src, pos)
            if not m:
                hide(text_from, len(src))
                break
            pos = m.end()
            if m.group() == "`":
                hide(text_from, m.start())
                pairs[templates.pop()] = m.start()
                text_from = None
            elif m.group() == "${":
                hide(text_from, m.start())
                braces.append(-1)
                text_from = None
            continue
        m = JS_TOKEN.search(src, pos)
        if not m:
            break
        token, at, pos = m.group(), m.start(), m.end()
        c = token[0]
        if len(token) > 1 and c == "/":
            hide(at, pos)
        elif len(token) > 1:
            if c == "'" and at and src[at - 1].isalnum():
                pos = at + 1  # an apostrophe after a letter is JSX text (Don't)
            else:
                hide(at + 1, pos - 1)
        elif c == "`":
            templates.append(at)
            text_from = pos
        elif c == "/":
            m = regex_can_start(src, at) and JS_REGEX.match(src, at)
            if m:
                pos = m.end()
                hide(at + 1, pos)
        elif c == "(":
            parens.append(at)
        elif c == ")":
            if parens:
                pairs[parens.pop()] = at
        elif c == "{":
            braces.append(at)
        elif c == "}" and braces:
            opener = braces.pop()
            if opener < 0:  # the end of a `${...}`: back to template text
                text_from = pos
            else:
                pairs[opener] = at
    out.append(src[last:])
    return "".join(out), pairs


class JsFile:
    def __init__(self, path, src):
        self.path, self.src = path, src
        self.msk, self.pairs = mask(src)
        self.newlines = [m.start() for m in re.finditer("\n", src)]
        self.defs = list(js_defs(self))
        self.tests = list(js_tests(self))
        self.imports, self.timers = js_imports(src)
        self.scopes = {}

    def line(self, offset):
        return bisect_left(self.newlines, offset) + 1


class Helper:
    """A named function in JS/TS test code, and whether a call to it asserts or sleeps."""

    def __init__(self, path, name, line, start, b0, b1):
        self.path, self.name, self.line = path, name, line
        self.start, self.b0, self.b1 = start, b0, b1
        self.asserts = self.sleeps = False
        self.ms = None  # the literal duration when it sleeps for a fixed time
        self.root = self  # the helper that fixed sleep is written in


def block_after(f, p):
    """(start, end) of the `{...}` block, or else the expression, at or after offset p."""
    msk = f.msk
    q = SPACE.match(msk, p).end()
    if msk[q : q + 1] == "{" and q in f.pairs:
        return q, f.pairs[q] + 1
    i = q
    while m := STOP.search(msk, i):
        c, i = m.group(), m.end()
        if c in "({":
            i = f.pairs.get(m.start(), m.start()) + 1
        elif (
            c != "\n"
            or m.start() > q
            and msk[SPACE.match(msk, i).end() :][:1] not in tuple(".?:&|+")
        ):
            return q, m.start()
    return q, len(msk)


def js_defs(f):
    """Yield (name, line, start, body start, body end) per named function."""
    msk = f.msk
    for m in JS_DEF.finditer(msk):
        if m.group("arrow"):
            body = block_after(f, m.end())
        else:
            close = f.pairs.get(m.end() - 1)
            if close is None:
                continue
            if m.group("decl") or m.group("fn"):
                brace = msk.find("{", close, close + 300)
                if brace not in f.pairs or ";" in msk[close:brace]:
                    continue
                body = brace, f.pairs[brace] + 1
            else:
                arrow = msk.find("=>", close, close + 300)
                if arrow < 0 or not re.fullmatch(
                    r"\s*(?::[^;=]*)?", msk[close + 1 : arrow]
                ):
                    continue  # `const x = (a + b) * 2`
                body = block_after(f, arrow + 2)
        yield m.group("decl") or m.group("name"), f.line(m.start()), m.start(), *body


def js_tests(f):
    """Yield (line, name, base, modifiers, call start, title end, end) per test."""
    msk = f.msk
    for m in JS_TEST.finditer(msk):
        mods = set(m.group(2).split(".")) - {""}
        i, j, title = m.end(), 0, -1
        for _ in range(3):
            if msk[i : i + 1] not in ("(", "`"):
                break
            j = SPACE.match(msk, i + 1).end()
            quote = msk[j : j + 1]
            if msk[i] == "(" and quote in ("'", '"', "`"):
                title = f.pairs.get(j, -1) if quote == "`" else msk.find(quote, j + 1)
                break
            close = f.pairs.get(i) if mods & CURRIED else None
            if close is None:
                break
            i = SPACE.match(msk, close + 1).end()
        if title < 0:
            continue
        # the longer of the call's parentheses and the callback's braces: a stray bracket
        # in JSX text then cuts neither short
        end = f.pairs.get(i, -1) + 1
        fn = JS_FN.search(msk, title, end or len(msk))
        if fn and fn.group() == "=>":
            end = max(end, block_after(f, fn.end())[1])
        elif fn:
            end = max(end, f.pairs.get(msk.find("{", fn.end()), -1) + 1)
        yield (
            f.line(m.start()),
            f.src[j + 1 : title],
            m.group(1),
            mods,
            i,
            title,
            end or len(msk),
        )


def js_imports(src):
    """([(is a re-export, module, [(local name, exported name)])] for modules of this repo,
    local names of node:timers/promises' setTimeout)."""
    imports, timers = [], set()
    for kind, names, spec in JS_IMPORT.findall(src):
        pairs = []
        for part in re.sub(r"[{}]", ",", names).split(","):
            words = part.split()
            if words == ["*"] and kind == "export":
                pairs.append(("*", "*"))
            elif words and words[0] not in ("*", "type"):
                pairs.append((words[-1], words[0]))
        if spec.endswith("timers/promises"):
            timers.update(local for local, name in pairs if name == "setTimeout")
        elif spec[0] == "." or spec[:2] in ("~/", "@/"):
            imports.append((kind == "export", spec, pairs))
    return imports, timers


@cache
def alias_root(folder, first):
    """The nearest folder at or above `folder` (or its src) that holds `first`: where a
    `~/first/...` or `@/first/...` import starts."""
    for base in (os.path.join(folder, "src"), folder):
        stem = os.path.join(base, first)
        if os.path.isdir(stem) or any(os.path.isfile(stem + e) for e in JS_EXTS[1:]):
            return base
    parent = os.path.dirname(folder)
    return alias_root(parent, first) if parent != folder else None


@cache
def resolve(spec, folder):
    """The file an import of `spec` from a file in `folder` names, or None."""
    if spec[0] == ".":
        base = os.path.normpath(os.path.join(folder, spec))
    else:
        root = alias_root(os.path.abspath(folder), spec[2:].split("/")[0])
        if not root:
            return None
        base = os.path.relpath(os.path.join(root, spec[2:]))
    stem = re.sub(r"\.[cm]?jsx?$", "", base)  # `./rig.js` in TypeScript is rig.ts
    for cand in (
        *(base + e for e in JS_EXTS),
        *(os.path.join(base, "index" + e) for e in JS_EXTS[1:]),
        *((stem + ".ts", stem + ".tsx") if stem != base else ()),
    ):
        if os.path.isfile(cand):
            return cand
    return None


JS_FILES = {}


def js_file(path, imported=False):
    f = JS_FILES.get(path)
    if f is None or (f is False and not imported):
        try:
            src = Path(path).read_text(errors="replace")
        except OSError:
            return None
        parse = (
            not imported
            or (TEST_DIRS | {"e2e"}) & set(Path(path).parts)
            or TEST_CODE.search(src)
        )
        f = JS_FILES[path] = JsFile(path, src) if parse else False
    return f or None


def js_calls(f, a, b, known):
    """[(offset, Helper, literal first argument)] per call in f.msk[a:b] to a name in known."""
    calls = []
    for m in JS_CALL.finditer(f.msk, a, b):
        helper = known.get(m.group(1))
        if helper and not f.msk[max(a, m.start() - 10) : m.start()].rstrip().endswith(
            "function"
        ):
            calls.append((m.start(), helper, millis(m.group(2))))
    return calls


def poll_loops(f, a, b):
    """Spans of the loops in f.msk[a:b] that can leave early: a sleep in one is a poll."""
    spans = []
    for m in JS_LOOP.finditer(f.msk, a, b):
        close = f.pairs.get(m.end() - 1)
        if close is None:
            continue
        end = close + 1 if m.group().endswith("{") else block_after(f, close + 1)[1]
        if LOOP_EXIT.search(f.msk, m.start(), end):
            spans.append((m.start(), end))
    return spans


def js_sleeps(f, a, b, known, calls):
    """([duration or None per sleep written in f.msk[a:b]], [(Helper, literal argument)] per
    call to a known function), both outside named inner functions and poll loops."""
    msk = f.msk
    hits = [
        *sleep_pattern(frozenset(f.timers)).finditer(msk, a, b),
        *PG_SLEEP.finditer(f.src, a, b),
    ]
    if not hits and not calls:
        return [], []
    skip = [(d[3], d[4]) for d in f.defs if a < d[2] < b] + poll_loops(f, a, b)
    naps = []
    for m in hits:
        if any(s <= m.start() < e for s, e in skip):
            continue
        if m.re is PG_SLEEP:
            naps.append(millis(m.group(1), 1000))
        elif m.group("timeout"):
            naps.append(millis(m.group("ms")))
        elif m.group("promise"):
            # an executor that hands its resolve to setTimeout
            open_ = m.end() - 1
            close = f.pairs.get(open_, open_)
            param = re.match(r"\(\s*(?:async\s*)?\(?\s*(\w+)", msk[open_:close])
            for timer in SET_TIMEOUT.finditer(msk, open_, close):
                end = f.pairs.get(timer.end() - 1)
                args = msk[timer.end() : end] if end else ""
                if param and re.search(rf"\b{param.group(1)}\b", args):
                    last = re.search(rf",\s*({NUM})\s*$", args)
                    naps.append(millis(last.group(1)) if last else None)
                    break
        else:
            name, arg = m.group("name"), m.group("arg")
            dotted = msk[m.start("name") - 1] == "."
            if name in f.timers and not dotted:
                naps.append(millis(arg))
            elif name == "setTimeout" or (dotted and not (arg and name == "sleep")):
                continue
            elif dotted or (name not in known and not m.group("none")):
                naps.append(millis(arg))
    return naps, [
        (helper, arg)
        for at, helper, arg in calls
        if not any(s <= at < e for s, e in skip)
    ]


def js_scope(f, level=0):
    """({name: Helper} for the functions a test in f can call, every Helper defined in f).
    A test file's imports are followed one file deep, and one more through `export ... from`."""
    if level in f.scopes:
        return f.scopes[level]
    names = {}
    for reexport, spec, pairs in f.imports:
        if level == 2 or (level == 1 and not reexport):
            continue
        target = resolve(spec, os.path.dirname(f.path))
        other = js_file(target, imported=True) if target else None
        if not other:
            continue
        theirs = js_scope(other, level + 1)[0]
        for local, name in pairs:
            if name == "*":
                names = {**theirs, **names}
            elif name in theirs:
                names[local] = theirs[name]
    own = [Helper(f.path, *d) for d in f.defs]
    known = {**names, **{h.name: h for h in own}}
    for h in own:
        h.calls = js_calls(f, h.b0, h.b1, known)
        h.naps, h.outer = js_sleeps(f, h.b0, h.b1, known, h.calls)
        h.asserts = bool(re.search(ASSERT["js"], f.msk[h.b0 : h.b1]))
    for _ in range(3):  # a helper that calls a helper
        for h in own:
            h.asserts = h.asserts or any(c.asserts for _, c, _ in h.calls)
            naps = h.naps + [c.ms if a is None else a for c, a in h.outer if c.sleeps]
            h.sleeps, h.ms = bool(naps), longest(naps)
            fixed = [c for c, a in h.outer if a is None and c.ms is not None]
            h.root = fixed[0].root if fixed and not h.naps else h
    spans = [(t[4], t[6]) for t in f.tests]
    for h in own:
        if not any(s < h.start < e for s, e in spans):
            names[h.name] = h
    f.scopes[level] = names, own
    return names, own


def judge(found, lg, where, code, helped):
    """File the test under each assertion smell its code shows; False without any assertion."""
    n_assert = len(re.findall(ASSERT[lg], code, re.MULTILINE))
    if not n_assert and not helped:
        found["no assertion"].append(where)
        return False
    if re.search(TAUTOLOGY[lg], code, re.MULTILINE):
        found["tautology (always passes)"].append(where)
    n_mock = len(re.findall(MOCK[lg], code, re.MULTILINE))
    n_snap = len(re.findall(SNAPSHOT[lg], code, re.MULTILINE))
    if n_mock and n_mock >= n_assert and not helped:
        found["asserts only on mocks"].append(where)
    if n_snap and n_snap >= n_assert and not helped:
        found["snapshot only"].append(where)
    return True


def scan_js(path, found, stats):
    f = js_file(path)
    if not f:
        return
    names, own = js_scope(f)
    stats["helpers"].update(
        (h.path, h.line) for h in (*names.values(), *own) if h.asserts
    )
    stats["each"] += len(JS_GROUP_EACH.findall(f.msk))
    lines = f.src.split("\n")
    for n, text in enumerate(f.msk.split("\n"), 1):
        if re.search(FILE_FOCUSED["js"], text):
            found[FOCUS].append(f"{path}:{n}  {lines[n - 1].strip()}")
        if re.search(FILE_SKIPPED["js"], text):
            found[SKIP].append(f"{path}:{n}  {lines[n - 1].strip()}")
    for n in sorted({f.line(m.start()) for m in JS_COND_SKIP.finditer(f.msk)}):
        found[COND_SKIP].append(f"{path}:{n}  {lines[n - 1].strip()}")
    # a sleep on fake timers takes no time
    hooks_fake = any(
        not any(t[4] < m.start() < t[6] for t in f.tests)
        for m in re.finditer(r"\buseFakeTimers\b", f.msk)
    )
    for line, name, base, mods, start, title, end in f.tests:
        stats["tests"] += 1
        stats["each"] += bool(mods & PARAMETRISED)
        where = f"{path}:{line}  {name}"
        if "only" in mods or base[0] == "f":
            found[FOCUS].append(where)
        if "fixme" in mods:  # listed as a conditional skip
            continue
        if mods & {"skip", "todo"} or base[0] == "x":
            found[SKIP].append(where)
            continue
        local = {h.name: h for h in own if start < h.start < end}
        known = {**names, **local} if local else names
        calls = js_calls(f, title + 1, end, known)
        helped = any(c.asserts for _, c, _ in calls)
        if not judge(found, "js", where, f.msk[title + 1 : end], helped):
            continue
        naps, outer = js_sleeps(f, title + 1, end, known, calls)
        for helper, arg in outer:
            if not helper.sleeps:
                continue
            if helper.ms is None or helper.name in local:
                naps.append(helper.ms if arg is None else arg)
            else:  # a helper with a fixed duration is listed once, not per test
                stats["sleepers"].setdefault(helper.root, set()).add(where)
        if naps:
            fake = hooks_fake or FAKE_TIMERS.search(f.msk, title, end)
            stats["sleeps"].append((longest(naps), where, bool(fake)))


def blocks(path, src):
    """Yield (line, name, body) per Ruby or Python test."""
    lines = src.splitlines()
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


def without_polls(code):
    """Ruby or Python code minus the loops that can leave early: a sleep in one is a poll."""
    lines = code.splitlines()
    for i, line in enumerate(lines):
        if re.match(r"\s*(while|until|for|loop)\b", line):
            ind = len(line) - len(line.lstrip())
            j = i + 1
            while j < len(lines) and (
                not lines[j].strip() or len(lines[j]) - len(lines[j].lstrip()) > ind
            ):
                j += 1
            if any(LOOP_EXIT.search(text) for text in lines[i:j]):
                lines[i:j] = [""] * (j - i)
    return "\n".join(lines)


def asserting_helpers(files):
    """Per language, the names of the Ruby and Python helper functions whose own body asserts:
    a call to one counts."""
    names = {"rb": set(), "py": set()}
    for path, src in files:
        lg = lang(path)
        lines = src.splitlines()
        pat = {"rb": RB_HELPER, "py": PY_HELPER}[lg]
        for i, line in enumerate(lines):
            m = pat.search(line)
            if not m:
                continue
            if lg == "rb" and re.search(r"\bdef\s+\w+[?!]?(\(.*?\))?\s*=", line):
                body = line  # endless def
            else:
                body = "\n".join(lines[i + 1 : block_end(lines, i, lg) + 1])
            if re.search(ASSERT[lg], body):
                names[lg].add(m.group(1))
    return names


def scan_plain(path, src, helper_call, found, stats):
    lg = lang(path)
    for n, text in enumerate(src.splitlines(), 1):
        if re.search(FILE_FOCUSED[lg], text):
            found[FOCUS].append(f"{path}:{n}  {text.strip()}")
        if re.search(FILE_SKIPPED[lg], text):
            found[SKIP].append(f"{path}:{n}  {text.strip()}")
        if re.search(COND_SKIPPED[lg], text):
            found[COND_SKIP].append(f"{path}:{n}  {text.strip()}")
    for line, name, body in blocks(path, src):
        stats["tests"] += 1
        where = f"{path}:{line}  {name}"
        # endless def: the code is what follows the "="
        code = "\n".join(body.splitlines()[1:] or [body.split("=", 1)[-1]])
        if re.search(FOCUSED[lg], body, re.MULTILINE):
            found[FOCUS].append(where)
        always = "\n".join(
            row for row in body.splitlines() if not re.search(COND_SKIPPED[lg], row)
        )
        if re.search(SKIPPED[lg], always, re.MULTILINE):
            found[SKIP].append(where)
            continue
        helped = bool(helper_call and helper_call.search(code))
        if judge(found, lg, where, code, helped):
            naps = [
                millis(m.group(1), 1000)
                for m in SLEEP[lg].finditer(without_polls(code))
            ]
            if naps:
                stats["sleeps"].append((longest(naps), where, False))


def collect(roots):
    """(test files, Ruby and Python support files such as test_helper.rb and conftest.py)."""
    tests, support = [], []

    def walk(top, with_tests):
        base = top.resolve().name
        for folder, dirs, names in os.walk(top):
            dirs[:] = sorted(set(dirs) - SKIP_DIRS)
            for name in sorted(names):
                p = Path(folder, name)
                if TEST_FILE.search(name):
                    if with_tests:
                        tests.append(p)
                elif p.suffix in {".rb", ".py"} and TEST_DIRS & {
                    base,
                    *p.relative_to(top).parts[:-1],
                }:
                    support.append(p)

    for root in map(Path, roots):
        if root.is_dir():
            walk(root, True)
            continue
        tests.append(root)
        home = next((d for d in root.resolve().parents if d.name in TEST_DIRS), None)
        if home and lang(root) != "js":
            walk(home, False)
    return list(dict.fromkeys(tests)), list(dict.fromkeys(support))


def scan(roots, only=None):
    """(counts for the header, {smell: [hit]}). `only` limits the test files that are
    reported; Ruby and Python helpers are still read from every root, and JS/TS helpers from
    the files a reported test file imports."""
    tests, support = collect(roots)
    chosen = [p for p in tests if not only or only(p)]
    plain = {
        p: p.read_text(errors="replace") for p in (*tests, *support) if lang(p) != "js"
    }
    helpers = asserting_helpers(plain.items())
    # Ruby calls need no parentheses
    call = {
        lg: re.compile(r"\b(" + "|".join(map(re.escape, sorted(names))) + r")" + tail)
        for lg, tail in (("rb", r"\b"), ("py", r"\s*\("))
        if (names := helpers[lg])
    }
    found = defaultdict(list)
    stats = {
        "all": len(tests),
        "files": len(chosen),
        "tests": 0,
        "each": 0,
        "helpers": {(lg, name) for lg in helpers for name in helpers[lg]},
        "sleeps": [],
        "sleepers": {},
    }
    for path in chosen:
        if lang(path) == "js":
            scan_js(str(path), found, stats)
        else:
            scan_plain(path, plain[path], call.get(lang(path)), found, stats)
    sleeps = list(stats["sleeps"])
    for h, callers in stats["sleepers"].items():
        tests = "1 test calls" if len(callers) == 1 else f"{len(callers)} tests call"
        where = f"{h.path}:{h.line}  {h.name}() helper sleeps, {tests} it"
        sleeps.append((h.ms, where, False))
    # longest first, unknown durations last, then the ones on fake timers
    sleeps.sort(key=lambda nap: (nap[2], nap[0] is None, -(nap[0] or 0)))
    for ms, where, fake in sleeps:
        notes = ([] if ms is None else [f"{ms:g} ms"]) + ["fake timers"] * fake
        found["fixed sleep"].append(
            f"{where}  ({', '.join(notes)})" if notes else where
        )
    return stats, found


def main():
    parser = argparse.ArgumentParser(
        description="Find tests that cannot fail or never run: no assertion, tautologies, "
        "mock- or snapshot-only assertions, focused or skipped tests, conditional skips, "
        "fixed sleeps. TypeScript/JavaScript, Ruby, Python. Every hit is a candidate to "
        "read, not a verdict.",
    )
    parser.add_argument(
        "roots",
        nargs="*",
        default=["."],
        metavar="ROOT",
        help="a folder to search for test files, or one test file (default: .)",
    )
    parser.add_argument(
        "--only",
        metavar="REGEX",
        help="report only the test files whose path matches REGEX (searched anywhere in the "
        "path, as given under ROOT); helper functions are still found outside those files",
    )
    parser.add_argument(
        "--list",
        metavar="FILE",
        help="report only the test files named in FILE, one path per line, relative to the "
        "current folder (the scope list); "
        "ROOT still says where helpers are read from",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help=f"print every hit of the lists to skim ({', '.join(SKIM)}); without it a list "
        f"of more than {SKIM_LIMIT} is printed as counts per file",
    )
    args = parser.parse_args()
    for root in args.roots:
        if not os.path.exists(root):
            parser.error(f"no such file or folder: {root}")
    only = flag = None
    if args.only and args.list:
        parser.error("give --only or --list, not both")
    if args.only:
        try:
            only, flag = re.compile(args.only), "--only"
        except re.error as e:
            parser.error(f"--only is not a regular expression: {e}")
        only = lambda p, rx=only: rx.search(str(p))
    elif args.list:
        try:
            rows = Path(args.list).read_text().splitlines()
        except OSError as e:
            parser.error(f"--list: {e}")
        listed = {os.path.realpath(row.strip()) for row in rows if row.strip()}
        wanted = len(listed)
        only, flag = (lambda p: os.path.realpath(p) in listed), "--list"
    stats, found = scan(args.roots, only)
    if not stats["all"]:
        parser.error(
            f"no test file found in: {' '.join(args.roots)} (test files are named "
            "*.test.ts, *.spec.js, *_test.rb, *_spec.rb, test_*.py, *_test.py)"
        )
    if not stats["files"]:
        parser.error(
            f"no test file under {' '.join(args.roots)} matches {flag} {args.only or args.list}"
        )
    of = f" of {stats['all']} ({flag})" if only else ""
    if args.list and stats["files"] < wanted:
        print(
            f"warning: {wanted - stats['files']} of {wanted} listed paths are not test "
            f"files under {' '.join(args.roots)}",
            file=sys.stderr,
        )
    print(
        f"files: {stats['files']}{of}  tests: {stats['tests']}  "
        f"parametrised (each) blocks: {stats['each']}  "
        f"asserting helpers: {len(stats['helpers'])}"
    )
    for smell in sorted(found, key=lambda s: -len(found[s])):
        print(f"\n{smell}: {len(found[smell])}")
        if smell in SKIM and len(found[smell]) > SKIM_LIMIT and not args.all:
            files = defaultdict(int)
            for w in found[smell]:
                files[re.sub(r":\d+  .*", "", w)] += 1
            print("  by file, most first (--all lists every test):")
            for name in sorted(files, key=lambda f: -files[f]):
                print(f"  {files[name]:4d}  {name}")
            continue
        for w in found[smell]:
            print(f"  {w}")


if __name__ == "__main__":
    main()
