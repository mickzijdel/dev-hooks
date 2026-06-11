# Off-topic improvements (noticed, out of scope)

From the 2026-06-11 plugin audit — considered and deliberately deferred, not forgotten:

- **dev-env templates still inline the jscpd cooldown one-liner.** This repo's `hk.pkl` and
  `ci.yml` now share `scripts/run-jscpd.sh`, but the dev-env-setup `hk.*.pkl`/`ci.*.yml`
  templates still carry the inline copy — moving them onto a shared script means shipping one
  more file per standard repo, i.e. a standard bump (v14) + fleet upgrade. Deferred until the
  cooldown logic next changes.
- **Checker tests live in the wrong file.** The `dev_env_check.sh` tests (`test_checker_*`,
  ~140 lines) sit in `tests/test_shell_hooks.py` but test a *skill script*, not a hook — they
  belong in `tests/test_skill_scripts.py`. Pure file move; harness already lives in conftest.
- **README opt-out docs mirror hook source comments.** Each `DEV_HOOKS_*` env var is documented
  in README.md "Notes" AND in its hook's header comment. Two sync points per hook; a generated
  README section (or a test asserting every hook's opt-out var appears in the README) would
  pin them together.
