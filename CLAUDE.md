Make sure to check all of the following and make sure they are up-to-date after making changes;
1. tool-specific documentation for tools you edited
2. skills for tools you edited
3. plugin.json
4. README.md
5. CLAUDE.md
6. tests/ — keep the pytest suite green and add coverage for behaviour you change
7. when editing a skill, check **all** its template/reference files (e.g.
   `skills/*/references/templates/`) — these mirror the standard the skill encodes and
   drift out of sync silently (e.g. a version stamp bumped in one template but not its
   siblings). Update every variant, not just the one you started with. For dev-env-setup
   the version stamps are machine-checked: `tests/test_dev_env_templates.py` asserts the
   templates, SKILL.md/standard.md current-version mentions, and the upgrade-guide chain
   all match `VERSION` (the hk `dev-env-version-sync` step runs it at commit time when
   skill or test files are staged). Bumping the standard = add the `## vN-1 → vN` guide section
   first; the tests enumerate every other spot to touch.

Bump the plugin version on every commit. Patch version for small fixes, minor version for more substantial changes (new skill or tool). The version lives **only** in `.claude-plugin/plugin.json` — marketplace.json deliberately carries no plugin version (Claude Code uses plugin.json's when both exist) and only a stable one-line description; don't re-add either.

Do not include changelog or detective-work where it does not belong, such as in the SKILL.md. This only belongs in dedicated changelog places.

## Authoring hooks (`hooks/scripts/*.sh`)

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
  so the normal permission flow proceeds). Stop hooks: `reminder_opt_out <OPT_VAR>`, `reminder_stop_init <sentinel>`
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
- Before claiming a hook works, run the full local CI: `uv run pytest -q`, `shfmt -d .`,
  `shellcheck **/*.sh`, and `bash scripts/run-jscpd.sh python,bash`. Let `shfmt -w` do the
  formatting — with `.editorconfig` it rewrites `case` patterns to `a | b)` and pushes `$(…)`
  heredocs onto their own line.
