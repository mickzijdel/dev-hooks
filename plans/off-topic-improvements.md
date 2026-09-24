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
- **adr skill has a dangling `[[agent-handoff]]` wikilink** (`plugins/thinking-tools/skills/adr/SKILL.md`)
  — either write that skill (upstream's 15-line `handoff` is a seed) or drop the link.
- **marketplace.json's thinking-tools description omits `adr`** (and now the three new skills);
  CLAUDE.md says descriptions stay stable, but if it's meant to enumerate skills it's drifting.

Noticed 2026-09-03 while shipping the prompt-log redaction:

- **hk's `gitleaks` step scans gitignored build artifacts.** A stale
  `tests/__pycache__/*.pyc` holding a *previous* version of a test fixture blocked a commit with
  a phantom finding that no longer existed in any tracked file. `gitleaks dir` walks the tree
  rather than reading only the staged blobs. Fix: scope the step with
  `gitleaks git --staged` (or add `--no-git`-safe excludes for `__pycache__`, `.venv`, `node_modules`)
  in `hk.pkl`, so a build artifact can never fail a commit.
- **`tests/test_hook_sunset_bets.py` classifies bets but never checks the reasoning behind a
  retire verdict.** Three weekly reviews argued `detect-stack-skills` should be deleted from fire
  counts alone, which cannot distinguish "redundant" from "working" (see
  `plans/automation-reviews/2026-09-03.md`). Candidate: have the weekly-automation-review skill
  require a mechanism probe — does the hook's advice point at anything that exists? — before any
  DELETE verdict, rather than a fire-count argument.
- **`reminder_changed_files` parses porcelain with `awk '{print $NF}'`.** That drops the source
  side of a rename (`R  old -> new` yields only `new`, which is usually what you want, but
  `R  "a b.rb" -> "c d.rb"` mis-splits) and mangles any path containing a space. Every Stop hook's
  file gate is built on it, including the new `reminder_session_files`. Fix: `git status
  --porcelain -z` with a NUL-delimited read, or `git diff --name-only HEAD` +
  `git ls-files --others --exclude-standard` instead of parsing status output at all.
- **Nothing gates a hook registered on an event that cannot run it.** `"type": "prompt"` and
  `"type": "agent"` hooks are only honoured on PreToolUse/PostToolUse/PermissionRequest; one
  configured on `Stop` or `UserPromptSubmit` is accepted by the loader and silently never fires.
  Candidate: a pytest over every plugin's `hooks.json` asserting non-command hook types appear
  only under tool events.

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
