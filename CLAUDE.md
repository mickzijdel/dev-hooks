This repo is a multi-plugin marketplace monorepo: `.claude-plugin/marketplace.json` at the
root serves four plugins from `plugins/{dev-hooks,coding-onboarding,thinking-tools,writing}/`,
each with its own `.claude-plugin/plugin.json`, `README.md`, and `skills/` (dev-hooks and
writing also ship `hooks/` — dev-hooks the main suite, writing a single `readme-reminder`).
Tests, tooling (`mise.toml`, `hk.pkl`, `.jscpd.json`, CI), and the root README stay
repo-wide.

The repo root also ships `install.sh` — a curl-able zero-dependency bootstrap that installs
Claude Code, signs the user in, installs the marketplace + the coding-onboarding plugin, and
opens an always-on-top browser checklist (`plugins/coding-onboarding/onboarding/onboard.html`).
It belongs to **coding-onboarding** despite living at root: edits to `install.sh` or
`onboard.html` bump that plugin's version (not "root tooling, bump nothing"). All
coding-onboarding user-facing text (install.sh output, onboard.html, the getting-started skill)
follows a plain-words rule for non-coders — no unexplained jargon, everyday analogies — with the
shared glossary in `plugins/coding-onboarding/skills/getting-started/references/plain-words.md`;
keep those three surfaces in step.

Make sure to check all of the following and make sure they are up-to-date after making changes;
1. tool-specific documentation for tools you edited
2. skills for tools you edited
3. the touched plugin's plugin.json
4. the touched plugin's README.md and the root README.md
5. CLAUDE.md
6. tests/ — keep the pytest suite green and add coverage for behaviour you change
7. when editing a skill, check **all** its template/reference files (e.g.
   `plugins/*/skills/*/references/templates/`) — these mirror the standard the skill encodes and
   drift out of sync silently (e.g. a version stamp bumped in one template but not its
   siblings). Update every variant, not just the one you started with. For dev-env-setup
   the version stamps are machine-checked: `tests/test_dev_env_templates.py` asserts the
   templates, SKILL.md/standard.md current-version mentions, and the upgrade-guide chain
   all match `VERSION` (the hk `dev-env-version-sync` step runs it at commit time when
   skill or test files are staged). Bumping the standard = add the `## vN-1 → vN` guide section
   first; the tests enumerate every other spot to touch. The same test file also asserts the
   CI templates stay **SHA-pinned** (`uses: owner/repo@<sha> # vX.Y.Z`) with a read-only
   `permissions:` block (the v16 standard) — when writing or reviewing any workflow, follow the
   `github-actions` skill's security checklist and verify pins with
   `skills/dev-env-setup/scripts/check_action_refs.sh`.

On every commit, bump the version of **each plugin whose files the commit touches** (patch for
small fixes, minor for more substantial changes — a new skill or tool). Commits touching only
root tooling/tests/docs bump nothing (or only marketplace.json's own version if its structure
changed). A plugin's version lives **only** in its `plugins/<name>/.claude-plugin/plugin.json` —
marketplace.json deliberately carries no per-plugin versions (Claude Code uses plugin.json's
when both exist) and only stable one-line descriptions; don't re-add either. The hk
`plugin-validate` step runs `claude plugin validate --strict` over the marketplace and every
plugin when plugin files are staged; it is the one hk step CI doesn't mirror (CI has no Claude
CLI).

Do not include changelog or detective-work where it does not belong, such as in the SKILL.md. This only belongs in dedicated changelog places.

## Authoring hooks (`plugins/dev-hooks/hooks/scripts/*.sh`)

- **The `writing` plugin's `readme-reminder.sh` is the one exception to everything below.**
  It lives in `plugins/writing/hooks/` and is deliberately self-contained — it does NOT source
  `reminder-common.sh`, because the `writing` plugin installs without `dev-hooks` and a cross-
  plugin `source` would break that standalone install. Its small reimplemented bits (opt-out
  case, jq payload read, `emit`) stay under jscpd's minTokens, so they don't trip the
  duplication gate against the lib — keep them terse if you extend them. Keep the script
  dependency-free; don't "DRY" it into the lib.
- **Reach for `hooks/scripts/lib/` first.** `reminder-common.sh` owns the payload-schema
  knowledge for the hooks. PostToolUse(Write|Edit|MultiEdit): `reminder_init <OPT_VAR>`
  (opt-out + INPUT/FILE/SESSION/TOOL/BASE in one jq spawn), `reminder_content` /
  `reminder_old_content` (CONTENT/OLD across Write content, Edit new/old_string, and
  MultiEdit edits[]), `reminder_fire_once <name> [extra]` (once-per-session marker; needs
  $SESSION from reminder_init), and `reminder_emit <msg>` (advisory additionalContext +
  exit 0). PreToolUse(Bash): `reminder_pre_init <OPT_VAR>` (opt-out + COMMAND/CWD/SESSION;
  reads `.tool_input.command` on its own so a multi-line command isn't truncated) and
  `reminder_emit_decision <deny|ask> <reason>` (emit the `permissionDecision` JSON + exit 0 —
  never emit `allow`, which would bypass the user's own allowlist; stay silent for safe commands
  so the normal permission flow proceeds). UserPromptSubmit (`prompt-log.sh`) has **no** init
  helper yet — it's the lone consumer of that event's payload, so it uses `reminder_opt_out` plus
  inline jq (nothing to drift); promote a `reminder_prompt_init` to the lib when a second
  UserPromptSubmit hook appears. Note that on exit 0 a UserPromptSubmit hook's stdout is injected
  into Claude's *context* (unlike PostToolUse's user-facing stdout), so such a hook must never
  print. Stop hooks: `reminder_opt_out <OPT_VAR>`, `reminder_stop_init <sentinel>`
  (INPUT/TRANSCRIPT + the once-per-session sentinel guard), `reminder_changed_files`
  (CHANGED from porcelain status), and `reminder_emit_stop <msg>` (continue:false + exit 2).
  Both kinds: `reminder_mktemp` (composable temp files — result in `$REPLY`, one shared
  cleanup trap; do NOT set your own `trap … EXIT`, it would clobber the lib's),
  `reminder_is_frontend_file`,
  and `reminder_is_test_path`. Shared embedded-python helpers (`git()`, `is_test_path()`)
  live in `lib/hook_helpers.py` — import them by passing `"$SELF_DIR/lib"` as an argv:
  `sys.dont_write_bytecode = True; sys.path.insert(0, sys.argv[N]); from hook_helpers import git`.
  Extend the lib rather than copying a jq expression or helper into a hook; a hook whose
  copy drifts doesn't error, it silently sees empty content and never fires. The bash
  `reminder_is_test_path` and python `is_test_path` deliberately mirror each other — change
  both or neither.
- **Embedded-python heredocs can't read piped stdin.** `python3 - <<'PYEOF'` consumes the
  heredoc as the program *source*, so `sys.stdin.read()` is empty even if you `printf … |`
  into it. Pass data via argv or a temp file instead — e.g. write to `mktemp`, then
  `python3 - "$CONTENT_FILE" <<'PYEOF'` and `open(sys.argv[1])` (see `verify-work.sh`,
  `review-reminder.sh`).
- **jscpd runs at threshold 0** (`.jscpd.json`, minTokens 70) and the CI `audit` job fails on
  ANY duplication. Shared python helpers belong in `lib/hook_helpers.py` (above); only when a
  block genuinely can't be shared that way, wrap it in `# jscpd:ignore-start` /
  `# jscpd:ignore-end` (valid python comments inside the heredoc; jscpd 5.x honors them).
- **Commit every script with the executable bit in the git index** (this repo has
  `core.fileMode=false`, so a plain `chmod +x` never reaches git — use
  `git update-index --chmod=+x <file>`). Plugin-cache installs and clones receive the index
  mode; a 100644 shebang script dies there with exit 126. The hk `exec-bit-scripts` step,
  the CI lint job, and `tests/test_exec_bits.py` all gate this (any tracked file whose first
  line is `#!`).
- Before claiming a hook works, run the full local CI: `uv run pytest -q`, `shfmt -d .`,
  `shellcheck **/*.sh`, and `bash scripts/run-jscpd.sh python,bash`. Let `shfmt -w` do the
  formatting — with `.editorconfig` it rewrites `case` patterns to `a | b)` and pushes `$(…)`
  heredocs onto their own line.
