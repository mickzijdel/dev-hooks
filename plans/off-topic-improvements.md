# Off-topic improvements (noticed, out of scope)

From the 2026-06-11 plugin audit — considered and deliberately deferred, not forgotten:

- **dev-env templates still inline the jscpd cooldown one-liner.** This repo's `hk.pkl` and
  `ci.yml` now share `scripts/run-jscpd.sh`, but the dev-env-setup `hk.*.pkl`/`ci.*.yml`
  templates still carry the inline copy — moving them onto a shared script means shipping one
  more file per standard repo, i.e. a standard bump (v14) + fleet upgrade. Deferred until the
  cooldown logic next changes.
