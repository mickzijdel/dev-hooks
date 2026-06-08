# Dropped from Nate's `dev-env-setup` — candidates to revisit

These are the parts of [Nate Berkopec's `dev-env-setup` skill](https://github.com/nateberkopec/dotfiles/tree/main/files/home/.claude/skills/dev-env-setup)
that the `dev-hooks:dev-env-setup` standard deliberately **left out** of v1, because none of
my current repos ([bedlam-bacs](https://github.com/EdinburghUniversityTheatreCompany/bacs-tool),
[readoc](https://github.com/mickzijdel/readoc),
[booking-overview](https://github.com/mickzijdel/booking-overview),
[vischeck](https://github.com/mickzijdel/vischeck)) use them. Kept here
so I can consider adopting them later — each would likely become a future `vN` entry in
[upgrade-guide.md](upgrade-guide.md).

| Dropped | What Nate does | Why I skipped it | Worth reconsidering when… |
|---------|----------------|------------------|---------------------------|
| **mise `[tasks]` as universal frontends** (`test`, `lint`, `serve`, `build`) | Every project exposes the same task names so tooling is uniform across repos | My repos call `uv run` / `bin/rails` directly via hk; no `[tasks]` table anywhere | I have ≥1 repo where I'd benefit from a uniform `mise run test` regardless of stack (e.g. a polyglot repo, or onboarding others) |
| **Ruby complexity gate** (RuboCop `Metrics`) | Fails on methods/classes over a complexity threshold | I run rubocop-rails-omakase, which disables Metrics by design | I want stricter Ruby and am willing to fight the cop |
| **`serve` task must log its URL in the last 10 lines** | Convention so tooling can scrape the dev URL | My repos are CLIs/libraries/plugins — no long-running `serve` | I standardise on a web app with a dev server worth auto-detecting |
| **`pitchfork` multi-process manager** | Runs multiple dev processes together | No multi-process dev setups currently | A repo needs web + worker + asset watcher running together |
| **`.env` via mise `_.file = ".env"` + `.env.example`** | mise auto-loads `.env`; `.env.example` documents keys | I use [fnox](https://fnox.jdx.dev) (see the `env-to-fnox` skill) for secrets; gitleaks guards plaintext | I hit a repo where fnox is overkill and a plain documented `.env.example` is the right call |

## Evaluated from jdx.dev "10 mise features" (2026-03)

Triage of [jdx.dev/posts/2026-03-02-10-mise-features](https://jdx.dev/posts/2026-03-02-10-mise-features/)
against the standard. Most features were already settled; the lockfile/supply-chain pair was the
one new adoption (now v2 — see [upgrade-guide.md](upgrade-guide.md)).

| Feature | Verdict | Notes |
|---------|---------|-------|
| **Lockfile (`mise lock`)** | **Adopted v2** | `mise.lock` + `lockfile = true` — reproducible, checksum-verified installs |
| **Supply-chain security** (checksums/Cosign/SLSA) | **Adopted v2** | comes with the lockfile via the aqua backend; pairs with gitleaks + Bundler cooldown |
| **GitHub/HTTP/S3 backends** | Skipped | only interesting to pin jscpd off `npx`; jscpd 5.x is npm-only Rust platform packages, no clean mise backend. Reconsider if jscpd ships standalone release binaries |
| **Tool stubs** (`mise generate tool-stub`) | Skipped | niche; the committed `mise.toml` already provisions every tool |
| **Task `sources`/`outputs`** | N/A | needs `[tasks]` (already dropped — see table above) |
| **Typed task args (`usage`)** | N/A | needs `[tasks]` |
| **Monorepo tasks** (experimental) | N/A | needs `[tasks]`; no monorepos |
| **`MISE_ENV` profiles** | Skipped | app/runtime-level config layering, like the dropped `.env`; not dev-tooling. Reconsider for a multi-env app repo |
| **Shell aliases** | Skipped | convenience only |
| **`mise prepare`** (experimental) | Watch | could replace the `uv sync` / `bundle install` steps once stable — revisit when it leaves experimental |
| **fnox** (ecosystem) | Already in use | see [[env-to-fnox]] |
| **hk** (ecosystem) | Already in use | core of the standard |
| **pitchfork** (ecosystem) | Already dropped | see table above (no multi-process dev setups) |

## Notes
- gitleaks **was** adopted (it's in the v1 standard) — it's the one secret-scanning piece from
  Nate I kept, as defense-in-depth alongside fnox.
- shellcheck / shfmt are **additions** of mine (not Nate's), so the standard can cover
  shell-script and Claude-Code-plugin repos like this one.
- **Duplication** (large-file + dead-code + duplication) was adopted into v1. Duplication uses
  two tools depending on stack — see the "Duplication: flay vs jscpd" note in `../SKILL.md` for
  why Ruby/Rails runs both (flay for Ruby structure, jscpd for the polyglot JS/CSS/ERB gate) and
  Python/shell run jscpd only.
