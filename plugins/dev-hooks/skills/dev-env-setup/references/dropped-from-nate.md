# Dropped from Nate's `dev-env-setup` — candidates to revisit

These are the parts of [Nate Berkopec's `dev-env-setup` skill](https://github.com/nateberkopec/dotfiles/tree/main/files/home/.claude/skills/dev-env-setup)
that the `dev-hooks:dev-env-setup` standard deliberately **left out** of v1, because the repos
this standard targets (a mix of Python CLIs/libraries, Claude Code plugin repos, and Rails apps)
didn't need them. Kept here as candidates to adopt later — each would likely become a future
`vN` entry in [upgrade-guide.md](upgrade-guide.md).

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
| **GitHub/HTTP/S3 backends** | Skipped | only interesting to pin jscpd off `npx`; no clean mise backend today — see the "jscpd as a mise tool" note below for the tested backends and revisit triggers |
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
  two tools depending on stack — see the "Duplication: flay vs jscpd" note in `standard.md` for
  why Ruby/Rails runs both (flay for Ruby structure, jscpd for the polyglot JS/CSS/ERB gate) and
  Python/shell run jscpd only.

### jscpd as a mise tool — deferred (tested 2026-06-09)

Making jscpd a *proper, pinned mise tool* (instead of unpinned `npx --yes jscpd@latest`) would
be nice, but every candidate backend was tested and none is worth adopting today:

- **`npm:jscpd`** — installs in <1s but **fails at runtime**: `jscpd: Platform package
  "cpd-linux-x64-gnu" not installed`. mise's `npm:` backend installs the wrapper package but not
  jscpd 5.x's *optional platform packages* (which carry the actual Rust binary); `npx` resolves
  optional deps, the mise npm backend does not. **Not viable.**
- **`cargo:jscpd`** — **works fully**: compiles from source (~34s, cached after), installs
  standalone `jscpd`/`cpd` binaries, honors `.jscpd.json` (verified `minTokens`/`threshold`,
  catches a synthetic clone, exits 1). But mise does **not** auto-provide cargo — it requires a
  **Rust toolchain** declared in `mise.toml` (or global on the host). Adding a whole Rust
  toolchain to every repo (Python/shell/Ruby) purely to pin a duplication checker isn't worth it.
- **`aqua:`/`ubi:`/`github:`** — jscpd's GitHub releases attach **no prebuilt binary assets**
  (verified: no `browser_download_url` on the latest releases), so there's nothing to download.

**Decision:** keep `npx --yes jscpd@latest`. **Revisit when** either (1) a repo already pins
`rust` for another reason — then switch *that* repo to `cargo:jscpd`; or (2) jscpd starts
attaching standalone release binaries to its GitHub releases — then use an `aqua`/`ubi` backend
(prebuilt, no Rust toolchain).
