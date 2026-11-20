"""The test-suite-tuning skill's test_smells.py, on small TypeScript, Ruby and Python test files."""

import subprocess
import sys
from pathlib import Path

SCRIPT = (
    Path(__file__).resolve().parent.parent
    / "plugins/dev-hooks/skills/test-suite-tuning/scripts/test_smells.py"
)

TS = """\
import { expect, it, test } from "vitest";
// a comment that says it (`x`) is fine must not count as a test
function expectClose(a: number, b: number, tol = 1): void {
  expect(Math.abs(a - b)).toBeLessThan(tol);
}
test("adds", () => expect(1 + 1).toBe(2));
test("uses a helper", () => { expectClose(0.1 + 0.2, 0.3); });
test("async", async () => { await expectAsync(p()).toBeRejected(); });
test("template", () => {
  const s = `a ${JSON.stringify({ x: 1 })} b`;
  expect(s).toContain("x");
});
test("nothing", () => { run(); });
it("placeholder", () => { expect(true).toBe(true); });
it.only("focused", () => { expect(f()).toBe(1); });
it.skip("later", () => {});
test("mock only", () => { const cb = vi.fn(); go(cb); expect(cb).toHaveBeenCalled(); });
test("sleeps", async () => { await page.waitForTimeout(500); expect(x).toBe(1); });
"""

RB = """\
require "test_helper"
class GateTest < ActiveSupport::TestCase
  test "checks" do
    pending = Gate.new(status: :pending)
    assert pending.pending?
  end
  def test_endless = assert(Gate.open?)
  test "nothing" do
    Gate.new.save
  end
  test "later" do
    skip "needs fixtures"
  end
  test "focus is on the input field" do
    assert_equal 1, f
  end
end
"""

PY = """\
import pytest
def test_ok():
    assert f() == 1
def test_nothing():
    f()
def test_multiline_signature(
    a,
):
    assert a
@pytest.mark.skip
def test_later():
    assert f()
"""


def _scan(tmp_path):
    (tmp_path / "a.test.ts").write_text(TS)
    (tmp_path / "gate_test.rb").write_text(RB)
    (tmp_path / "test_gate.py").write_text(PY)
    out = subprocess.run(
        [sys.executable, "-I", str(SCRIPT), str(tmp_path)],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    found, smell = {}, None
    for line in out.splitlines():
        if (
            line
            and not line.startswith(" ")
            and ": " in line
            and not line.startswith("files:")
        ):
            smell = line.rsplit(":", 1)[0]
            found[smell] = []
        elif line.startswith("  ") and smell:
            found[smell].append(line.split("  ", 2)[-1].strip())
    return out, found


def test_finds_each_smell(tmp_path):
    out, found = _scan(tmp_path)
    assert "tests: 19" in out
    assert sorted(found["no assertion"]) == ["nothing", "nothing", "test_nothing"]
    assert found["tautology (always passes)"] == ["placeholder"]
    assert found["focused (.only): the rest of the file never runs"] == ["focused"]
    assert sorted(found["skipped or todo"]) == ["later", "later", "test_later"]
    assert found["asserts only on mocks"] == ["mock only"]
    assert found["fixed sleep"] == ["sleeps  (500 ms)"]


def test_helpers_async_expects_and_templates_count_as_assertions(tmp_path):
    _, found = _scan(tmp_path)
    flagged = {name for names in found.values() for name in names}
    for fine in (
        "uses a helper",
        "async",
        "template",
        "checks",
        "test_endless",
        "test_multiline_signature",
        "adds",
    ):
        assert fine not in flagged
    # a word in a test name is not a focus marker
    assert "focus is on the input field" not in flagged


def _run(root, *args):
    return subprocess.run(
        [sys.executable, "-I", str(SCRIPT), str(root), *args],
        capture_output=True,
        text=True,
        check=True,
    ).stdout


def test_group_level_focus_and_skip_markers(tmp_path):
    (tmp_path / "g.test.ts").write_text(
        'describe.only("a", () => {\n  fit("f", () => { expect(1).toBe(1); });\n'
        '  xit("x", () => { expect(1).toBe(1); });\n});\n'
        'fdescribe("b", () => {});\nxdescribe("c", () => {});\n'
    )
    (tmp_path / "g_test.rb").write_text(
        "class GTest < Minitest::Test\n  focus\n  def test_one = assert(true)\nend\n"
    )
    (tmp_path / "g_spec.rb").write_text(
        'RSpec.describe G do\n  fit "f" do\n    expect(1).to eq 1\n  end\n'
        '  xit "x" do\n    expect(1).to eq 1\n  end\n'
        '  it "subject" do\n    is_expected.to be_valid\n  end\nend\n'
    )
    out = _run(tmp_path)
    focused = out.split("focused")[1].split("\n\n")[0]
    for where in (
        'g.test.ts:1  describe.only("a"',
        "g.test.ts:2  f",
        'g.test.ts:5  fdescribe("b"',
        "g_test.rb:2  focus",
        "g_spec.rb:2  f",
    ):
        assert where in focused, (where, out)
    skipped = out.split("skipped or todo")[1].split("\n\n")[0]
    for where in ("g.test.ts:3  x", 'g.test.ts:6  xdescribe("c"', "g_spec.rb:5  x"):
        assert where in skipped, (where, out)
    assert "no assertion" not in out, out  # is_expected counts


def test_helpers_count_only_by_their_own_body(tmp_path):
    test_dir = tmp_path / "test"
    test_dir.mkdir()
    (test_dir / "test_helper.rb").write_text(
        "def check_valid(x)\n  assert x.valid?\nend\n"
    )
    (test_dir / "a_test.rb").write_text(
        'class ATest < Minitest::Test\n  test "uses helper" do\n    check_valid(x)\n  end\nend\n'
    )
    (test_dir / "test_b.py").write_text(
        "import pytest\n@pytest.fixture\ndef client():\n    return make()\n"
        "def test_nothing(client):\n    client.get('/')\n"
        "def test_ok(client):\n    assert client.get('/').ok\n"
    )
    out = _run(test_dir)  # the documented command: the test folder as the root
    assert "uses helper" not in out, out  # test_helper.rb is found from the root `test`
    assert "test_nothing" in out, out  # the fixture is not an asserting helper


def test_apostrophes_and_block_comments_do_not_swallow_the_next_test(tmp_path):
    (tmp_path / "j.test.tsx").write_text(
        "test(\"renders\", () => {\n  render(<p>Don't</p>); /* it's fine */\n});\n"
        'test("checks", () => { expect(f()).toBe(2); });\n'
    )
    out = _run(tmp_path)
    assert "no assertion: 1" in out and "renders" in out, out
    assert "tautology" not in out, out


def _cli(*args):
    return subprocess.run(
        [sys.executable, "-I", str(SCRIPT), *map(str, args)],
        capture_output=True,
        text=True,
    )


def _found(out):
    """{heading: [hit text after the path:line]} from the scanner's output."""
    found, smell = {}, None
    for line in out.splitlines():
        if line.startswith("  ") and smell:
            found[smell].append(line.split("  ", 2)[-1].strip())
        elif line and not line.startswith("files:"):
            smell = line.rsplit(":", 1)[0]
            found[smell] = []
    return found


COND_SKIP = "conditional skip: check the condition is not something the lane provides"


def test_a_file_root_is_scanned_and_a_missing_or_empty_root_exits_2(tmp_path):
    one = tmp_path / "one.test.ts"
    one.write_text('it("nothing", () => { run(); });\n')
    (tmp_path / "empty").mkdir()
    (tmp_path / "empty" / "code.ts").write_text("export const x = 1;\n")
    out = _run(one)
    assert "files: 1  tests: 1" in out and "no assertion: 1" in out, out
    missing = _cli(tmp_path / "nope")
    assert missing.returncode == 2 and "nope" in missing.stderr, missing
    assert missing.stdout == ""
    empty = _cli(tmp_path / "empty")
    assert empty.returncode == 2 and "no test file" in empty.stderr, empty


def test_only_reports_matching_files_and_help_names_it(tmp_path):
    (tmp_path / "rig.ts").write_text(
        "export function check(x: number) {\n  expect(x).toBe(1);\n}\n"
    )
    (tmp_path / "hunt-a.test.ts").write_text(
        'import { check } from "./rig";\n'
        'it("helped", () => { check(1); });\nit("bare", () => { run(); });\n'
    )
    (tmp_path / "other.test.ts").write_text('it("unrelated", () => { run(); });\n')
    out = _run(tmp_path, "--only", r"hunt-.*\.test")
    assert "files: 1 of 2 (--only)  tests: 2" in out, out
    assert _found(out) == {"no assertion": ["bare"]}, out
    usage = _cli("--help")
    assert usage.returncode == 0 and "--only REGEX" in usage.stdout, usage


def test_js_helpers_count_per_file_and_only_when_called(tmp_path):
    (tmp_path / "a.test.ts").write_text(
        "const headers = (h: Headers) => {\n"
        '  expect(h.get("x")).toBe("1");\n};\n'
        'it("uses the helper", () => {\n  headers(new Headers({ x: "1" }));\n});\n'
        'it("names the headers helper only", () => {\n'
        "  // headers(x) in a comment is no call\n"
        "  const headers = build();\n  run(headers);\n});\n"
    )
    (tmp_path / "rig").mkdir()
    (tmp_path / "rig" / "index.ts").write_text('export * from "./checks";\n')
    (tmp_path / "rig" / "checks.ts").write_text(
        "export const expectRow = (r: Row) => {\n  expect(r.id).toBe(1);\n};\n"
        "export const viaOther = (r: Row) => {\n  expectRow(r);\n};\n"
    )
    (tmp_path / "b.test.ts").write_text(
        'import { viaOther as checkRow } from "./rig";\n'
        'it("imported helper", () => {\n  checkRow(row());\n});\n'
        'it("sends only the headers", () => {\n'
        '  send(new Headers({ x: "1" }));\n'
        "  expect(fetchMock).toHaveBeenCalledOnce();\n});\n"
        'it("other file helper", () => {\n  headers(1);\n});\n'
    )
    out = _run(tmp_path)
    found = _found(out)
    assert sorted(found["no assertion"]) == [
        "names the headers helper only",
        "other file helper",
    ], out
    assert found["asserts only on mocks"] == ["sends only the headers"], out
    assert "asserting helpers: 2" in out, out  # headers, and viaOther as checkRow


EACH = """\
it.each(ROUTES.map((r) => [r.method, r.path]))(
  "refuses %s %s",
  async (m, p) => {
    await call(m, p);
  },
);
it.each([
  { page: (id?: string) => Page({ id }) },
])("gates $page", async ({ page }) => { await page(); });
it.each`
  a    | b
  ${f(1)} | ${2}
`("table $a", ({ a, b }) => { expect(a).toBe(b); });
it.only.each([[fn()]])("focused each", () => {});
it.skip.each([[fn()]])("skipped each", () => {});
it.concurrent("concurrent", async () => { await go(); });
it.sequential("sequential", async () => { await go(); });
it.fails("fails", () => { expect(1).toBe(2); });
test.for([[fn(1)]])("for %s", ([a]) => { expect(a).toBe(1); });
it.skipIf(isCI())("skip if", () => { expect(f()).toBe(1); });
it.runIf(isCI())("run if", () => { go(); });
describe.each(TABLE.map((t) => [t]))("group %s", (t) => {
  it("inside", () => { expect(t).toBeTruthy(); });
});
"""


def test_each_forms_and_vitest_modifiers_are_tests(tmp_path):
    (tmp_path / "each.test.ts").write_text(EACH)
    out = _run(tmp_path)
    found = _found(out)
    assert "tests: 12  parametrised (each) blocks: 7" in out, out
    assert sorted(found["no assertion"]) == [
        "concurrent",
        "focused each",
        "gates $page",
        "refuses %s %s",
        "run if",
        "sequential",
    ], out
    assert found["focused (.only): the rest of the file never runs"] == [
        "focused each"
    ], out
    assert found["skipped or todo"] == ["skipped each"], out
    assert len(found[COND_SKIP]) == 2, out


def test_a_regex_literal_with_a_brace_does_not_end_the_body(tmp_path):
    (tmp_path / "re.test.ts").write_text(
        'it("regex", () => {\n'
        "  const found = /\\nfunction calc\\([\\s\\S]*?\\n\\}\\n/.exec(text)?.[0];\n"
        "  const half = (a + b) / 2;\n"
        "  const quoted = files.filter((file) => /[\"'`]exempt/.test(file));\n"
        "  expectTypeOf<typeof found>().toEqualTypeOf<string>();\n"
        "  expect(found).toBeDefined();\n});\n"
        'it("typed", () => {\n  expectTypeOf<A>().toEqualTypeOf<B>();\n});\n'
        'it("next", () => { run(); });\n'
    )
    assert _found(_run(tmp_path)) == {"no assertion": ["next"]}


SLEEPS = """\
import { setTimeout as nap } from "node:timers/promises";
import { settle } from "./rig";
import { retry } from "../retry";
const pause = (ms: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, ms));
it("typed helper", async () => {
  await pause(LIMIT_MS * 1.75);
  expect(x).toBe(1);
});
it("typed helper literal", async () => {
  await pause(1_200);
  expect(x).toBe(1);
});
it("block executor", async () => {
  await new Promise((r) => {
    setTimeout(r, 300);
  });
  expect(x).toBe(1);
});
it("pg", async () => {
  await pool.query("SELECT pg_sleep(2)");
  expect(x).toBe(1);
});
it("timers alias", async () => { await nap(50); expect(x).toBe(1); });
it("unknown delay", async () => { await delay(IDLE); expect(x).toBe(1); });
it("settles one", async () => { await settle(); expect(x).toBe(1); });
it("settles two", async () => { await settle(); expect(x).toBe(1); });
const renderIt = async () => {
  await settle();
};
it("settles through a wrapper", async () => { await renderIt(); expect(x).toBe(1); });
it("faked", async () => {
  vi.useFakeTimers();
  const done = pause(60_000);
  await vi.advanceTimersByTimeAsync(60_000);
  await done;
  expect(x).toBe(1);
});
it("fake latency", async () => {
  const fetch = async () => {
    await new Promise((resolve) => setTimeout(resolve, 5));
  };
  await runAll(fetch);
  expect(peak).toBe(2);
});
it("poll", async () => {
  while (Date.now() < deadline) {
    if (await blocked()) break;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  expect(await blocked()).toBe(true);
});
it("code under test sleeps", async () => { await retry(); expect(x).toBe(1); });
it("code under test asserts", async () => { await retry(); });
it("timeout guard", async () => {
  await new Promise((resolve, reject) => {
    setTimeout(() => reject(new Error("late")), 5000);
    job.on("done", resolve);
  });
  await waitFor(() => expect(x).toBe(1));
});
"""


def test_sleep_forms_durations_order_and_polls(tmp_path):
    (tmp_path / "__tests__").mkdir()
    (tmp_path / "__tests__" / "rig.ts").write_text(
        "export const settle = () => new Promise((r) => setTimeout(r, 20));\n"
    )
    (tmp_path / "__tests__" / "s.test.ts").write_text(SLEEPS)
    (tmp_path / "retry.ts").write_text(
        "export async function retry() {\n  assertReady(job);\n"
        "  await new Promise((r) => setTimeout(r, 1000));\n}\n"
    )
    (tmp_path / "s_test.rb").write_text(
        'class S < Minitest::Test\n  test "naps" do\n    sleep 0.5\n'
        "    assert x\n  end\nend\n"
    )
    (tmp_path / "test_s.py").write_text(
        "import time\ndef test_polls():\n    while True:\n        if done():\n"
        "            break\n        time.sleep(0.1)\n    assert done()\n"
        "def test_naps():\n    time.sleep(3)\n    assert done()\n"
    )
    found = _found(_run(tmp_path))
    assert found == {
        "no assertion": ["code under test asserts"],
        "fixed sleep": [
            "test_naps  (3000 ms)",
            "pg  (2000 ms)",
            "typed helper literal  (1200 ms)",
            "naps  (500 ms)",
            "block executor  (300 ms)",
            "timers alias  (50 ms)",
            "settle() helper sleeps, 3 tests call it  (20 ms)",
            "typed helper",
            "unknown delay",
            "faked  (60000 ms, fake timers)",
        ],
    }


def test_conditional_skips_get_their_own_heading(tmp_path):
    (tmp_path / "c.spec.ts").write_text(
        'describe.skipIf(Boolean(process.env.SMTP))("unset", () => {\n'
        '  it("inside", () => { expect(x).toBe(1); });\n});\n'
        'test.describe("playwright", () => {\n'
        "  test.beforeEach(async () => {\n"
        '    test.skip(!(await mockRunning()), "mock is down");\n  });\n'
        '  test("under hook", async () => { expect(x).toBe(1); });\n'
        '  test.fixme("broken", async () => {});\n'
        '  test.skip("plain skip", async () => {});\n});\n'
        'test.describe.skip("off", () => {});\n'
    )
    out = _run(tmp_path)
    found = _found(out)
    assert [hit.split("(")[0] for hit in found[COND_SKIP]] == [
        "describe.skipIf",
        "test.skip",
        "test.fixme",
        "test.describe.skip",
    ], out
    assert found["skipped or todo"] == ["plain skip"], out
    assert "no assertion" not in found, out


def test_header_counts_files_tests_each_blocks_and_helpers(tmp_path):
    out, _ = _scan(tmp_path)
    assert out.splitlines()[0] == (
        "files: 3  tests: 19  parametrised (each) blocks: 0  asserting helpers: 1"
    )


def test_list_reports_only_the_files_of_the_scope_list(tmp_path):
    (tmp_path / "a.test.ts").write_text('it("bare a", () => { run(); });\n')
    (tmp_path / "b.test.ts").write_text('it("bare b", () => { run(); });\n')
    scope = tmp_path / "scope.txt"
    scope.write_text(f"{tmp_path / 'b.test.ts'}\ngone/c.test.ts\n\n")
    partly = _cli(tmp_path, "--list", scope)
    assert "1 of 2 listed paths are not test files" in partly.stderr, partly
    out = partly.stdout
    assert "files: 1 of 2 (--list)" in out, out
    assert _found(out) == {"no assertion": ["bare b"]}, out
    scope.write_text("elsewhere/c.test.ts\n")
    none = _cli(tmp_path, "--list", scope)
    assert none.returncode == 2 and "--list" in none.stderr, none


def test_a_long_skim_list_is_printed_as_counts_per_file(tmp_path):
    body = "".join(
        f'it("calls {i}", () => {{ run(); expect(spy).toHaveBeenCalled(); }});\n'
        for i in range(26)
    )
    (tmp_path / "many.test.ts").write_text(body)
    (tmp_path / "few.test.ts").write_text(body.split("\n")[0] + "\n")
    out = _run(tmp_path)
    assert "asserts only on mocks: 27" in out and "calls 3" not in out, out
    rows = out.split("--all lists every test):\n")[1].splitlines()
    assert rows[0].split()[0] == "26" and rows[0].endswith("many.test.ts"), out
    assert "calls 3" in _run(tmp_path, "--all")


def test_ruby_and_python_conditional_skips_are_not_plain_skips(tmp_path):
    (tmp_path / "a_test.rb").write_text(
        "class ATest < Minitest::Test\n"
        "  def test_needs_redis\n"
        '    skip "no redis" unless ENV["REDIS_URL"]\n'
        "    assert_equal 1, 1 + 0\n"
        "  end\n"
        "  def test_later\n"
        '    skip "only works if redis is up"\n'
        "  end\n"
        "end\n"
    )
    (tmp_path / "test_b.py").write_text(
        "import pytest\n\n\n"
        '@pytest.mark.skipif(not HAS_GPU, reason="no gpu")\n'
        "def test_gpu():\n    assert run() == 1\n"
    )
    out = _run(tmp_path)
    assert "conditional skip" in out and "skipped or todo: 1" in out, out
    assert "a_test.rb:6  test_later" in out, out
    assert "a_test.rb:3" in out and "test_b.py:4" in out, out
