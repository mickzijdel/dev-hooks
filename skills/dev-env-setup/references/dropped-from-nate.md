# Dropped from Nate's `dev-env-setup` — candidates to revisit

These are the parts of [Nate Berkopec's `dev-env-setup` skill](https://github.com/nateberkopec/dotfiles/tree/main/files/home/.claude/skills/dev-env-setup)
that the `dev-hooks:dev-env-setup` standard deliberately **left out** of v1, because none of
my current repos (`bedlam-bacs`, `readoc`, `booking-overview`, `vischeck`) use them. Kept here
so I can consider adopting them later — each would likely become a future `vN` entry in
[upgrade-guide.md](upgrade-guide.md).

| Dropped | What Nate does | Why I skipped it | Worth reconsidering when… |
|---------|----------------|------------------|---------------------------|
| **mise `[tasks]` as universal frontends** (`test`, `lint`, `serve`, `build`) | Every project exposes the same task names so tooling is uniform across repos | My repos call `uv run` / `bin/rails` directly via hk; no `[tasks]` table anywhere | I have ≥1 repo where I'd benefit from a uniform `mise run test` regardless of stack (e.g. a polyglot repo, or onboarding others) |
| **Large-file detection** (symlinked `tools/check_large_files.rb`) | Pre-commit step that blocks accidentally-committed big files | gitleaks + normal review has been enough; no incidents | I commit binaries/datasets, or after the first "oops, 50 MB blob in history" |
| **Ruby complexity gate** (RuboCop `Metrics`) | Fails on methods/classes over a complexity threshold | I run rubocop-rails-omakase, which disables Metrics by design | I want stricter Ruby and am willing to fight the cop |
| **Dead-code detection** (`debride` via `tools/check_dead_code.rb`) | Flags unused Ruby methods | Not used in any repo; noisy on Rails | A long-lived Rails app accumulates cruft I want to prune |
| **Duplication checks** (`flog`, `flay`) | Flags high-churn / copy-pasted Ruby | Same as above — overkill for current project sizes | A codebase grows big enough that duplication is a real maintenance cost |
| **`serve` task must log its URL in the last 10 lines** | Convention so tooling can scrape the dev URL | My repos are CLIs/libraries/plugins — no long-running `serve` | I standardise on a web app with a dev server worth auto-detecting |
| **`pitchfork` multi-process manager** | Runs multiple dev processes together | No multi-process dev setups currently | A repo needs web + worker + asset watcher running together |
| **`.env` via mise `_.file = ".env"` + `.env.example`** | mise auto-loads `.env`; `.env.example` documents keys | I use [fnox](https://fnox.jdx.dev) (see the `env-to-fnox` skill) for secrets; gitleaks guards plaintext | I hit a repo where fnox is overkill and a plain documented `.env.example` is the right call |

## Notes
- gitleaks **was** adopted (it's in the v1 standard) — it's the one secret-scanning piece from
  Nate I kept, as defense-in-depth alongside fnox.
- shellcheck / shfmt are **additions** of mine (not Nate's), so the standard can cover
  shell-script and Claude-Code-plugin repos like this one.
