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
            and not line.startswith("tests")
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
    assert found["fixed sleep"] == ["sleeps"]


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


def _run(root):
    return subprocess.run(
        [sys.executable, "-I", str(SCRIPT), str(root)],
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
