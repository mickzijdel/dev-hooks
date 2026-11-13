# Off-topic improvements (noticed, out of scope)

Noticed 2026-07-02 while reviewing mattpocock/skills for vendoring:

- **Debugging feedback-loop material** (upstream `engineering/diagnosing-bugs`): the 10-way
  catalogue for constructing a repro loop (failing test, curl script, replay a captured trace,
  bisection harness, differential loop, …), "tighten the loop" (faster / sharper signal /
  deterministic), and raising the reproduction *rate* for flaky bugs instead of chasing a clean
  repro. No home yet — superpowers:systematic-debugging owns the trigger; revisit if that ever
  moves in-house.
- **Tagged debug prefixes** (`[DEBUG-a4f2]` on every temporary log so cleanup is one grep) —
  would pair well with the dev-hooks `debug-leftover-reminder` hook, e.g. the hook could
  suggest the convention in its reminder text.
- **Tautological-test anti-pattern** (assertion recomputes the expected value the same way the
  code does, so it passes by construction) — candidate for the missing-test-reminder text or a
  testing-guidance reference.
- **Vertical-slice / tracer-bullet framing** for breaking plans into independently-shippable
  issues (each slice cuts through all layers, demoable on its own) — useful language for
  plan-writing guidance.

Noticed 2026-11-13 by the `one-fix` skill's two test runs on this repo (subagent findings,
not verified by hand):

- **Two parsers for "which git command, in which directory".** `reminder_runs_git` (awk
  segments) and `git_target_dir` in `hook_helpers.py` (shlex) disagree: `timeout 5 git -C
  /other push` matches in awk while `git_target_dir` returns the session cwd, and a `cd`
  inside a quoted heredoc body moves the python answer. Proposal: `reminder_runs_git` also
  tracks `cd`/`-C` and returns the directory and operands, so the python function, the
  tokeniser in `worktree-provision-reminder.sh` and the loop in `dangerous-command-guard.sh`
  go.
- **python3 is required in practice but guarded as optional.** The jq mirror of
  `session_start` and the over-report fallbacks in `reminder-common.sh` only run when
  python3 is missing, while other paths fail silently without it. One check at source time
  would let about 80 lines and `test_jq_stamp_mirror_agrees_with_python` go. Behaviour
  change: Stop hooks go silent without python3.
- **`timeout` → `gtimeout` → perl ladder exists once** (`verify-work.sh`), with weaker copies
  in `worktree-setup/scripts/setup-worktree.sh` and none in
  `dev-env-setup/scripts/fleet_roster.sh` (`bounded` has no fallback on a bare macOS).
- **`github_readme_audit.py` has three fence readers**: `heading_lines` got a fix and a fix
  to that fix; `fenced_code_blocks` and `first_non_heading_paragraph` still have the old
  behaviour.
- **No macOS CI job**: every job runs `ubuntu-latest`, and the recent portability fixes
  (BSD sed, no `/proc`, no `timeout`, bash 3.2) are one class a macOS job would catch.

Noticed 2026-09-22 while shipping the `deslop` skill:

- **`slop_scan.py`'s `is_code()` miscounts C-family block comments.** A line inside a
  `/* … */` block counts as *code* unless it starts with `*`, so a C/Java/Go file using
  bare-indented block comments inflates the code denominator and deflates its measured
  comment density. The budgets in `deslop/references/measurements.md` were calibrated with
  this behaviour in place and on `#`-comment languages, so fixing it moves every published
  number: it is a re-measurement task (re-run the four reference corpora, update the tables)
  rather than a one-line fix. Until then the density metric is trustworthy for `#`-comment
  languages and approximate for the C family.
- **The scanner has no way to mark a file as legitimately slop-shaped.** Its own test
  fixtures and its own rule definitions hit `debug-residue`, `generic-name` and
  `type-suppression` by construction, because the strings *are* the patterns. Every run
  against this repo carries those four known-false hits. Options: a `# slop-scan: ignore-file`
  escape hatch, or per-rule `skip_in_tests` following `reminder_is_test_path` /
  `is_test_path`. Deliberately not done now — suppressing a rule inside test paths also hides
  real debug residue in tests, and that trade needs a decision rather than a default.
- **deslop's swallowed-error rule has no pattern for Ruby's modifier `rescue`.** `x = f rescue nil`
  swallows every StandardError on one line and is the idiomatic Ruby form of the bug, but the
  rule only matches block `rescue` followed by `nil`/`end` on the next line. Found while fixing
  the Python bare-except anchor; left out because it is a missing pattern, not that bug. Needs a
  precision check against a real Ruby corpus first — `rescue nil` in a guard clause is sometimes
  deliberate.

- **Stop hooks still start python 9-11 times per Stop.** The session-start cache (dev-hooks
  2.49.1) removed the 7 spawns that only re-derived it; what remains is distinct work —
  untracked_since, untracked_text, transcript_invoked, missing-test's is_test_path — at
  ~19ms (~35ms via the mise shim) each. A lazily-started python coprocess in
  reminder-common.sh (bash 4 `coproc`; the lib already needs bash 4 for mapfile) would take
  every hook to one spawn, at the cost of a request/response protocol that must carry
  arbitrary file text, and a fallback when the coprocess dies. Worth it only if Stop
  latency becomes noticeable again.
- **A general "speed up a slow test suite" skill.** Only rails-toolkit covers suite profiling.
  The pytest pass here (durations → parallel-safety check → xdist → shared expensive
  fixtures → chunk the one long sweep) generalises to parallel_tests / vitest threads and
  would fit dev-hooks next to dependency-upgrade.

Noticed 2026-10-03 while adding Stop-nudge outcome tracking to the mod:

- **The vischeck PostToolUse reminder fires on `hooks/register.tsx`** (a mod module with no UI
  route) — `.tsx` alone isn't a view.

- **verify-work's cap marker on a timeout-only message**: the marker also prints when the only
  message is the slow-suite advisory (or, since 2.65.22, the slow-check one). Harmless today
  (that nudge resolves `unknown`), but gate it on `$TMPFILE` being non-empty if the advisory
  ever gets a remedy.

Noticed 2026-10-22 during the dev-env v28 fleet backfill:

- **Rails' default `bin/brakeman` passes `--ensure-latest`**, so a fleet repo's `scan_ruby` job goes
  red the day Brakeman releases, whatever the code (spotify-tools since 8.1.0, 2026-10-15). The
  Ruby part of the standard could say whether to keep that flag, and the dependency-upgrade skill
  could treat it as a known red.
- **scav-hunt's herb steps are broken on untouched master**: herb 0.10.3 resolves the newest
  `parallel` (2.3.0) against the locked 2.2.0, and `npx @herb-tools/linter` 0.11.1 needs Node
  ≥ 22.12 for `@ruby/prism`'s ES module (the repo pins 22.4.1). Worth checking whether other Ruby
  fleet repos pin herb or Node the same way.
- **The status pane shows Working while a permission prompt waits** (deferred from its final
  review, 2026-10-25). AskUserQuestion and the guard's dialog read as Waiting on you; a plain
  permission prompt can't be told apart from a long-running tool, and in auto mode the
  classifier, not the person, answers it. Revisit if a `tool.check` verdict says who will answer.

Noticed 2026-10-25 while draining this backlog:

- **verify-work never runs ESLint in a repo with only one config style**
  (found while capping the linters). Its gate is `ls .eslintrc* eslint.config.* >/dev/null 2>&1`, and
  `ls` exits non-zero when either glob matches nothing, so ESLint runs only where both a legacy
  `.eslintrc*` and a flat `eslint.config.*` exist. Fixing it starts running ESLint at Stop in
  every JS repo with a config, so it wants a check of what that costs on Mick's JS repos first.

Noticed 2026-10-28 while researching skill routing:

- **thinking-tools-nudge.sh's keyword cues matched 3 of 1,313 typed prompts (Oct 3–28)**, and the
  skill listing drops descriptions for 69 of 144 skills (least-invoked first), including
  but-for-real, self-rate and grill. Raise `skillListingBudgetFraction` before tuning the nudge;
  consider retiring the nudge in a Retire pass. Details in
  `plans/automation-reviews/research/2026-10-28-working-with-claude.md`.

Noticed 2026-10-28 while provisioning a BlackLightning worktree:

- **worktree-setup's `setup-worktree.sh` rewrote the main checkout's mise lockfiles**, reported
  by a subagent and not reproduced. The main checkout's `mise/mise.lock` (−166 lines) and
  `mise/mise.development.lock` (+6 lines) changed 2 s after the worktree's overlay was written,
  with the same diff the worktree got; the subagent restored them with `git checkout --`.
  Suspect the `mise x -- bash -c "$POST_CMD"` step (around line 182) resolving from the main
  checkout's cwd, with BL's `lockfile = true`. Reproduce with a scratch worktree and
  `git status` on main before and after.

- **github_readme_audit.py's command-example checks only know package managers** (2026-10-28,
  found while writing vicinae-updater's README). SETUP/USAGE_COMMAND_HINTS in
  `plugins/writing/skills/github-readme/scripts/github_readme_audit.py` match package managers and
  script runs, so an ops README for a private tool (systemd units, a CLI on PATH) fails both
  though its sections have ```sh blocks. Either skip those checks when the README has no package
  manifest next to it, or accept any fenced command under the Installation/Usage heading, and say
  in the failure which commands the checks look for. The PostToolUse hook re-raises these on
  every README edit.

- **The dev-env standard's floating jscpd breaks `audit` across ERB repos** (2026-10-28, found
  while triaging Dependabot PRs). `run-jscpd.sh` (root and the dev-env-setup template) runs the
  newest jscpd at least 4 days old. jscpd 5.4.2 (released 10-20, eligible from 10-24) finds ERB
  clones that 5.4.1 did not: booking-overview main went from 0 clones to 7, and spotify-tools to 2.
  With the threshold at 0, `audit` fails on every CI run in those repos from 10-24, so every PR
  there looks broken. Either pin jscpd in the standard and let Dependabot/renovate bump it, or
  keep the float but fix the new clones fleet-wide in one sweep. Seen by a subagent on
  booking-overview; not re-run here.
- **Decide mise-action v5 once in the standard** (2026-10-28). The templates pin
  `jdx/mise-action` v4.2.0 (`references/templates/ci.*.yml`), while Dependabot proposes v5.x
  repo by repo (booking-overview#116, spotify-tools#88, impamp-3#85, five on affinity since 10-15).
  v5's only breaking change is a 24 h minimum release age for the mise binary. Bump the
  templates (v29) or add a Dependabot `ignore` for the major in the template's dependabot.yml.
- **vulture scans in-repo worktrees** (2026-10-28, from PR #31's review). vulture collects every
  `*.py` recursively and only `--exclude` filters it. `hk.pkl:47` and both hk templates exclude
  neither `.claude/worktrees` nor `.worktrees`, so the main checkout's pre-commit also scans every
  in-repo worktree. PR #31 (v26) fixed the first, but v26 was used for something else; redo it as
  v29 covering both, together with #34's `concurrency:` cancel-superseded-runs block (also in
  rails-toolkit#9).
- **commit-digest treats its own unmerged PRs as shipped** (2026-10-28). `skipped-suggestions.md`
  (PR #4) marks later ideas "Duplicate" of agent-handoff (#8) and quiz-me (#13), which never
  merged. Its novelty check reads that log (`commit-digest/SKILL.md:54`), so closing those PRs
  leaves skips justified by code that does not exist. Have the novelty check confirm a
  "duplicate of" target is on main, and re-open the affected skips if #8/#13 close.
- **verify-work's nudge scoring can't see "named and offered"** (2026-10-29). Since 2.69.0 a
  failure the session didn't cause is to be named in the reply with the fix offered under Your
  move, but `resolveNudge`'s verify-work case only knows passed / still failing, so that reply
  scores as ignored. A remedy that reads the next reply for the failing check's name (from the
  block's `=== name ===` sections) would make the acted-on rate mean something again.
- **The standards-sweep routine covers 6 of ~20 dev-env repos** (2026-10-29). Cloud routine
  "Maintain dev-hook standards" (`trig_01AShWmktsvqAUydEJWduzaN`) attaches only dev-hooks,
  black_lightning (now the EUTC repo, fixed 2026-10-29), vischeck, booking-overview, fringe-chat and
  spotify-tools. impamp-3, aisafety-radar, the website, rails-toolkit and the other tools never get
  swept. Add them, or derive the source list from the fleet roster.
- **Nine skill descriptions are still 300+ characters after the 79cac7a trim** (2026-10-29, measured
  as the raw `description:` line on origin/main 510de9e): thinking-toolbox 337, voice-profile 334,
  self-rate 333, grill 309, expose-service 309, repo-review 306, review-queue 304, loop-oversight 304,
  deslop 300. Either the trim measured differently (quotes, folded YAML) or these regrew. Pick one
  measure, add it to `tests/test_marketplace.py` (or a skills test) as a hard cap, and trim these.
- **dev-env-setup tooling assumes a root `mise.toml`/`mise.lock`** (2026-10-29, found upgrading EUTC
  black_lightning from v23 to v28, which keeps both under `mise/`). Three gaps (fleet_roster.sh already reads all of these locations): (1) the `check_version_sync.sh` template reads only inline `[tools]` entries, not
  `[tools.ruby]` tables with `version =`, so BL carries its own patched reader. (2) The same template
  hardcodes a root `mise.lock`, so with `mise/config.toml` it silently skips `mise/mise.lock`, and v27's
  "mise.lock always joins the comparison" doesn't hold. (3) `dev_env_check.sh` reads neither
  `mise/config.toml` nor `mise/mise.lock`, and doesn't accept AGENTS.md in place of CLAUDE.md, so BL
  reports `repo_version=0` / `needs-upgrade`. Support mise's documented config locations
  (`mise.toml`, `.mise.toml`, `mise/config.toml`, `.config/mise/config.toml`) in all three, and treat
  AGENTS.md as satisfying the CLAUDE.md check.
- **In-repo worktrees: mise relocks the parent checkout, and jscpd can scan 0 files** (2026-10-29,
  EUTC black_lightning). The `mise/mise.lock` −166 / `mise.development.lock` +6 relock described
  above recurred: `mise install` in `.worktrees/<x>` also read and relocked the main checkout's config.
  Separately, jscpd run inside that worktree scanned 0 files in 130 ms and passed (a `git archive`
  copy found the real result, 0 clones of 1,428 files), so a worktree's jscpd pass can be vacuous.
  spotify-tools' worktree did scan normally, so check BL's `.jscpd.json` / gitignore handling. Make
  `run-jscpd.sh` fail when it scanned 0 files. Checked 2026-11-09 (jscpd 5.4.3, a dev-hooks
  worktree under `.claude/worktrees/`, which scanned all 90 files): the `ai` and `threshold`
  reporters that `.jscpd.json` sets print no file count, so the runner needs one from elsewhere
  (add the `console` reporter and read its "Files analyzed" total, or a second `-r json` run).
  Passing `-r` overrides each repo's configured reporters, and the runner is a standard template,
  so this lands with a standard version bump.
- **`setup-worktree.sh` line ~149 prints "command substitution: ignored null byte in input"**
  (2026-10-29, seen provisioning a mick-zijdel-website worktree). A `$(…)` there reads a file or
  command output containing a NUL byte. Find which input (likely a binary file matched by a copy
  glob) and filter it, or read it with a NUL-safe method.
- **CI watch misses a push of an already-seen SHA to a second remote** (2026-10-29). scav-hunt's
  2dbbefc was pushed first to the fork (Actions off, so the watcher reported "no run") and then to
  `upstream` (EUTC, where CI ran and FAILED). No result was ever reported for the second push, so a
  red EUTC master went unnoticed until a side agent flagged it. Key the watch on remote + SHA (read
  the repo from the push output's `To <url>` line), not on SHA alone.
- **CI watch misattributes a quiet push** (2026-10-29). `cd ~/…/spotify-tools && git push -q origin main`
  printed nothing, so the mod's `CI watch` had no push output to parse and announced it was watching
  `mickzijdel/dev-hooks@75f605b` (the session cwd's repo and HEAD) instead of spotify-tools@d73a3ca.
  When the push output is empty, resolve the repo from the command's own `cd`/`-C` target (as
  `reminder_git_target_dir` does) and its pushed ref, or say nothing; never fall back to the cwd repo.
- **dev-env Ruby hk template: the `test` step bypasses the `t` queue** (2026-10-29, v29 backfill). In the Ruby repos' `hk.pkl` (booking-overview, spotify-tools, scav-hunt, from the Ruby template) the pre-commit `test` step runs `bin/rails test` directly, so a commit staging `.rb` files starts a full parallel suite outside `~/.local/bin/t`'s machine-wide queue. With parallel agents that swapped the laptop before. Make the template call `t` when it's on PATH (falling back to `bin/rails test` in CI).
- **v28 → v29 guide step 5: the `shfmt -w` rule retabs 2-space repos** (2026-10-29). "Run `shfmt -w` in a repo without an `.editorconfig`" would reindent the whole re-copied script to tabs in repos with no shfmt gate whose committed copy is 2-space (booking-overview, spotify-tools, prose-arena, scav-hunt, impamp-3); the agents skipped it there. Say "where the repo lints shell with shfmt" instead.
- **worktree-setup: a worktree shares the main checkout's uv venv when `UV_PROJECT_ENVIRONMENT` is set** (2026-10-29, readwise-digest v29 backfill). readwise-digest's `mise.toml` points `UV_PROJECT_ENVIRONMENT` at `~/.local/share/readwise-digest/venv`, the venv its live daily timer runs from, so `uv run` in a worktree re-pointed that venv's editable install at the worktree (repaired by `uv sync --frozen` from the main checkout). Have `setup-worktree.sh` give each worktree its own `UV_PROJECT_ENVIRONMENT` (e.g. `<worktree>/.venv`) in the env it writes, when the repo sets one outside the checkout.
- **dev_env_check.sh: a local-only repo can never be compliant** (2026-10-29). readwise-digest and prose-arena have no git remote, so `has_ci=0` keeps them at `status=needs-setup` even at the current version. Treat a repo with no remote as exempt from the CI gate (report it as `local-only`), or say in the guide that these stay `needs-setup` by design.
- **Small v30 follow-ups** (2026-10-29, from the v30 bump): `ci.shell.yml`'s ruff step lists `*.py` but not `*.pyi`, while the hk builtin covers both; `dev_env_check.sh` doesn't gate the ruff minor pin (only `check_version_sync.sh` catches drift); server-setup's five Python files are linted by nothing (decide whether it gets ruff); the v29 → v30 guide's server-setup paragraph says "only step 8 applies" though "Which steps apply" also has it re-copy the sync script.
- **data-before-design-reminder sends chart-for-a-post prompts to the wrong skill** (2026-11-02). Its noun list includes `charts?|graphs?`, so "make a chart for my LinkedIn post" gets a nudge that asks for loading, error and empty states, which a posted image never has. The data-before-design skill now points on to `practical-charts`, but the nudge itself does not. When the matched noun is chart/graph/table and the prompt names a post, thread, deck, report or newsletter, name `practical-charts` in the nudge as well (or instead).
- **hk `bundler-audit` blocks a commit that only partly fixes the advisories** (2026-11-05, v31 Rails sweeps in jambook, spotify-tools, booking-overview). With the cooldown holding back a fix (Rails 8.1.4.1, nokogiri), every patch/minor `Gemfile.lock` commit failed on advisories already on main; two agents committed with `HK_SKIP_STEPS=bundler-audit`, and the auto-mode classifier denied the third. Candidate for v32: the pre-commit step fails only on advisories the staged lockfile adds compared with HEAD's, and the full check stays in CI's scan job. The one-package bypass (`bundle update <gems> --conservative --cooldown=0`) moved only the named gems and their Rails component gems in all three repos.
- **fringe-chat pins `exclude-newer` to an absolute date** (2026-11-05). `backend/pyproject.toml` has `exclude-newer = "2026-10-25T00:00:00Z"` under a comment saying uv's pyproject parser rejects durations; uv ≥ 0.9.17 accepts `"3 days"` (every other fleet repo uses it), so the window is stale and drifts further each day. Switch to `"3 days"` and relock.

- **CI runs Linux only, so BSD breakage ships silently** (2026-11-08). plan-reminder's GNU-only
  `stat -c %Y` never fired on macOS, and nested-run detection read `/proc` only (both fixed
  2026-11-09). Consider a macOS CI job.
- **lint-on-edit.sh's `find_root` loops forever on a relative `file_path`** (2026-11-09).
  `dirname .` is `.`, never `/`. Claude Code sends absolute paths, so it has not bitten; stop when
  `dirname` returns its input.
