# Off-topic improvements (noticed, out of scope)

- `plugins/writing/skills/github-readme/scripts/github_readme_audit.py` — the heading and
  command-hint patterns don't know common modern spellings: `## Install` (vs
  `Installation`) fails the section check, and `uv`, `mise`, `claude`/`/plugin` commands
  don't count as setup/usage examples. Extend `SECTION_PATTERNS` with
  `r"^#{1,6}\s+install\b"` and add `uv|mise` to the command hints (golden tests in
  `tests/test_skill_scripts.py` need regenerating; bump the writing plugin).
