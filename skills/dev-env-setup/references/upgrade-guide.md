# dev-env standard — upgrade guide

The current standard version is in [`../VERSION`](../VERSION). Each repo records the version
it targets via `DEV_ENV_VERSION` in its `mise.toml`. When a repo's stamp is behind, apply every
section **strictly newer** than the repo's current version, in order, then re-stamp
`DEV_ENV_VERSION` to the new version and re-run the checker.

To find a repo's current version:

```bash
grep DEV_ENV_VERSION mise.toml   # absent ⇒ treat as v0
```

---

## v0 → v1 (baseline)

v0 = "has hk + mise + CI but predates this standard" (e.g. `bedlam-bacs`, `readoc`,
`booking-overview` as they exist today: ruff/pytest or rubocop/rails-test via hk, CI mirroring
it, but **no gitleaks step and no version stamp**). To reach v1:

1. **Add the version stamp.** Add to `mise.toml`:
   ```toml
   [env]
   DEV_ENV_VERSION = "1"
   ```
2. **Add gitleaks to hk.** Add the import and a gitleaks step to `hk.pkl`:
   ```pkl
   import "package://github.com/jdx/hk/releases/download/v1.46.0/hk@1.46.0#/Builtins.pkl"
   // inside the `linters` mapping:
   ["gitleaks"] = Builtins.gitleaks
   ```
   (Match the `amends` version already pinned in the file; bump both together if you like.)
3. **Add `gitleaks` to mise tools:** `gitleaks = "latest"` under `[tools]`.
4. **Add a gitleaks job to CI** mirroring the hook (see `templates/ci.*.yml` — the
   `gitleaks/gitleaks-action@v2` job with `fetch-depth: 0`).
5. **Verify:** `mise install && hk install && hk run check` (gitleaks must run clean), then
   `bash scripts/dev_env_check.sh .` → `status=compliant`.

A repo with **no** dev-env setup at all goes straight to the full v1 layout — copy
`templates/{mise,hk,ci}.<stack>.*` and fill in stack specifics.

**Claude Code plugin / script-bundle repos** additionally need (part of v1): a readoc-style
dev-only `pyproject.toml` (`templates/pyproject.plugin.toml`), a `tests/` suite running each
bundled script as a subprocess (`templates/test_scripts.example.py`), and `uv run --script` +
PEP 723 inline metadata on every Python script. See the "Claude Code plugin repos" section in
`../SKILL.md`.

---

## Adding a future version

When the standard changes, bump `../VERSION`, then add a `## vN-1 → vN` section here listing the
exact migration steps. The skill and the reminder hook pick up the new number automatically (both
read `../VERSION`). Candidate future bumps are parked in
[`dropped-from-nate.md`](dropped-from-nate.md).
