"""README ↔ hook-source parity.

Every DEV_HOOKS_* env var a hook honours (opt-outs and tunables) is documented in two
places by construction: the hook's own header comment and the README. That's two sync
points per hook with nothing pinning them together — this test is the pin: any var
referenced by a hook script must appear in README.md.
"""

import re

from conftest import HOOKS, ROOT

ENV_VAR = re.compile(r"DEV_HOOKS_[A-Z][A-Z_]*")


def test_every_hook_env_var_is_documented_in_readme():
    readme_vars = set(ENV_VAR.findall((ROOT / "README.md").read_text()))
    missing = {}
    # Top-level hook scripts only: lib/ helpers document vars generically ("DEV_HOOKS_X")
    # and are covered through the hooks that pass them real names.
    for script in sorted(HOOKS.glob("*.sh")):
        undocumented = set(ENV_VAR.findall(script.read_text())) - readme_vars
        if undocumented:
            missing[script.name] = sorted(undocumented)
    assert not missing, f"hook env vars not documented in README.md: {missing}"
