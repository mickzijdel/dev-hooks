# Off-topic improvements (noticed, out of scope)

- **jscpd 5.0.4 ignores the `.jscpd.json` `ignore` list — repo-wide CI/pre-commit breakage.**
  As of 2026-06-09 the 4-day cooldown in `scripts/run-jscpd.sh` resolves **jscpd 5.0.4**, and
  in that version `bash scripts/run-jscpd.sh python,bash` reports the template `run-jscpd.sh`
  as a clone of `scripts/run-jscpd.sh` and fails at 0.7% > 0% threshold — even though
  `.jscpd.json` lists the templates dir under `ignore`. Verified empirically: NO `ignore`
  entry suppresses it (tested `templates/**`, `templates/**/*`, `**/templates/**`, and even
  `**/run-jscpd.sh` — none work), so the `ignore` key is being dropped entirely on the
  `jscpd . -f …` invocation, not a glob-pattern problem. `threshold`/`minTokens` are still
  honored, so the config file is read; only `ignore` is non-functional. Main CI was green on
  2026-06-12 (older jscpd) and will go red on the next push. This blocks every commit until
  fixed and is unrelated to any feature change. Fix candidates: pin jscpd below 5.0.4 in the
  cooldown floor; pass ignores via CLI (`--ignore`) or a `.jscpdignore` file instead of the
  config key; or restructure so the template isn't a byte-for-byte copy of the runner. Touches
  the dev-env standard (run-jscpd.sh is templated), so coordinate with dev-env-setup.
