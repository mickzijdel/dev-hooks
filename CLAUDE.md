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
   siblings). Update every variant, not just the one you started with.

Bump the plugin version on every commit. Patch version for small fixes, minor version for more substantial changes (new skill or tool).

## Authoring hooks (`hooks/scripts/*.sh`)

- **Embedded-python heredocs can't read piped stdin.** `python3 - <<'PYEOF'` consumes the
  heredoc as the program *source*, so `sys.stdin.read()` is empty even if you `printf … |`
  into it. Pass data via argv or a temp file instead — e.g. write to `mktemp`, then
  `python3 - "$CONTENT_FILE" <<'PYEOF'` and `open(sys.argv[1])` (see `verify-work.sh`,
  `review-reminder.sh`).
- **jscpd runs at threshold 0** (`.jscpd.json`, minTokens 70) and the CI `audit` job fails on
  ANY duplication. If two hooks must share identical embedded-python helpers (`git()`,
  `is_test_path()`, …), wrap the shared block in `# jscpd:ignore-start` / `# jscpd:ignore-end`
  (valid python comments inside the heredoc; jscpd 5.x honors them).
- Before claiming a hook works, run the full local CI: `uv run pytest -q`, `shfmt -d .`,
  `shellcheck **/*.sh`, and `npx --yes jscpd@latest . -f python,bash`. Let `shfmt -w` do the
  formatting — with `.editorconfig` it rewrites `case` patterns to `a | b)` and pushes `$(…)`
  heredocs onto their own line.