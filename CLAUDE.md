This repo is a multi-plugin marketplace monorepo: `.claude-plugin/marketplace.json` at the
root serves four plugins from `plugins/{dev-hooks,coding-onboarding,thinking-tools,writing}/`,
each with its own `.claude-plugin/plugin.json`, `README.md`, and `skills/` (dev-hooks,
writing and thinking-tools also ship `hooks/` — see "Authoring hooks" below).
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
plugin when plugin files are staged; CI runs the same validation through `tests/test_mods.py`
on the dev-hooks plugin.

Do not include changelog or detective-work where it does not belong, such as in the SKILL.md. This only belongs in dedicated changelog places.

## The dev-hooks mod (`plugins/dev-hooks/hooks/register.tsx`)

`hooks.json` names one function-hook module under `modules`, beside the command hooks; its
state contract is `plugins/dev-hooks/types/index.d.ts` (named as `types` in plugin.json) and
its tests are `plugins/dev-hooks/tests/*.test.ts(x)`, run by `claude plugin test
plugins/dev-hooks` via `tests/test_mods.py` (skipped where there's no Claude CLI; CI's `test`
job installs a pinned one, needing no login). tsc can't run in CI — only a logged-in session
load writes `.claude-plugin/types/` — so type-check locally after a session has loaded the
plugin (`npx -p typescript tsc -p plugins/dev-hooks`; the engine writes that `tsconfig.json`). Load the `plugin-authoring` skill before editing it. A Claude Code
that predates mods, or has them switched off, skips the module and still runs every command
hook. `claude plugin validate` refuses `$` passed into the `read`/`update` state helpers the
bundled examples use; call `$.state.get`/`$.state.set` directly.

The module also records **session facts** (`facts:<session id>` in `$.store`, typed as `Facts` in
`types/index.d.ts`): skills, subagent dispatches, per-repo edits with net growth (`root: null`
outside any repo), and the `classic.Stop` verdict. Rules learned building it:
- `$` is followed only into functions declared in `register.tsx`, never across an import — shared
  code in another file must be pure. One unmatched `on(event)` per event per module: add to the
  existing `session.start` hook rather than registering a second.
- Persist facts in `$.store`, not `$.state` (which a reboot or resume loses). The store has no
  compare-and-set and tool calls run in parallel, so every read-modify-write goes through the
  module's `changeFacts` queue.
- A `classic.Stop` hook sees the command hooks' verdict folded **last-write-wins**: with several
  blocking, only the last reason reaches the module (Claude still gets them all). A mod can't
  merge the shell Stop nudges from outside; that logic has to move into the module.
- In `claude plugin test`, the test's own `$` has no `store`/`state` noun and `$.classic` is
  undefined: answer `session.id`/`store.*`/`process.run` from a Map via the test's `on`
  (`{ value: … }`), as `tests/session-facts.test.ts` does. Run tsc too — `validate` misses a
  wrong call shape such as `$.process.run({ argv })`.

## Authoring skills (`plugins/*/skills/*/SKILL.md`)

- **Descriptions are trigger lists, not feature dumps** — every model-invocable description
  sits in the context window every turn, so it earns harder pruning than the body. Front-load
  when to fire; the body holds the rest.
- **No-op test, per sentence**: does this line change behaviour versus what the model does by
  default? If not, delete the sentence — don't trim words from it.
- **Prefer a leading word over a restated triad**: one strong pretrained word ("tight",
  "red", "relentless") anchors behaviour in fewer tokens than "fast, deterministic,
  low-overhead" ever will.
- **Completion criteria must be checkable** ("every modified file accounted for", not "be
  thorough") — a vague criterion invites stopping early.
- Push material only some runs need into `references/*.md` (progressive disclosure); keep
  what every run needs in SKILL.md.

## Authoring hooks (`plugins/dev-hooks/hooks/scripts/*.sh`)

- **The standalone-plugin hooks never source dev-hooks' lib.** The `writing` plugin
  (`readme-reminder.sh`, the four `voice-*.sh`) and the `thinking-tools` plugin
  (`thinking-tools-reminder.sh`, `thinking-tools-nudge.sh`) live in their own
  `plugins/*/hooks/` and must NOT source `reminder-common.sh` or import `hook_helpers.py`:
  those plugins install without `dev-hooks`, and a cross-plugin `source` would break that
  standalone install. Sharing *within* a plugin is fine and preferred — the writing hooks
  ship together, so they share `plugins/writing/hooks/scripts/lib/voice-common.sh`
  (`voice_opt_out [VAR]`, `voice_payload`/`voice_field`, `voice_profile`,
  `VOICE_PROSE_EXTS` + `voice_is_prose_file`, `voice_transcript_scan`,
  `voice_state_file`/`voice_fire_once`, `voice_emit <event> <msg>`, `voice_emit_stop`, and
  the `DEV_HOOKS_FIRE_LOG` telemetry those emits record). `VOICE_PROSE_EXTS` is passed into
  `voice_transcript_scan`'s python heredoc by argv rather than re-listed there — a drifted
  copy of an extension list doesn't error, it just silently stops seeing files.
  `thinking-tools`' two hooks have no sibling to share with, so their small reimplemented
  bits stay terse and under jscpd's minTokens.
- **Reach for `hooks/scripts/lib/` first.** `reminder-common.sh` owns the payload-schema
  knowledge for the hooks. PostToolUse(Write|Edit|MultiEdit): `reminder_init <OPT_VAR>`
  (opt-out + INPUT/FILE/SESSION/TOOL/BASE in one jq spawn), `reminder_content` /
  `reminder_old_content` (CONTENT/OLD across Write content, Edit new/old_string, and
  MultiEdit edits[]), `reminder_fire_once <name> [extra]` (once-per-session marker; needs
  $SESSION from reminder_init), and `reminder_emit <msg>` (advisory additionalContext +
  exit 0), and `reminder_emit_correction <msg>` (stderr + exit 2 — the louder PostToolUse
  path for a hook that fires on every occurrence, used by `inline-svg-reminder.sh`).
  SessionStart: `reminder_session_init` (INPUT/DIR/SESSION; no opt-out argument, since these
  hooks gate differently from one another — a plain env var, a CLAUDE.md marker, an ownership
  heuristic — so each calls `reminder_opt_out` itself) and `reminder_emit_session <msg>`
  (additionalContext injected into Claude's context + exit 0).
  PreToolUse(Bash): `reminder_pre_init <OPT_VAR>` (opt-out + COMMAND/CWD/SESSION;
  reads `.tool_input.command` on its own so a multi-line command isn't truncated) and
  `reminder_emit_decision <deny|ask> <reason>` (emit the `permissionDecision` JSON + exit 0 —
  never emit `allow`, which would bypass the user's own allowlist; stay silent for safe commands
  so the normal permission flow proceeds). UserPromptSubmit: `reminder_prompt_init <OPT_VAR>`
  (opt-out + INPUT/PROMPT/CWD/SESSION; reads `.prompt` on its own so a multi-line prompt isn't
  truncated — shares the `reminder_cwd_session` tail with `reminder_pre_init`) and
  `reminder_emit_prompt <msg>` (advisory additionalContext + exit 0), used by both `prompt-log.sh`
  and `intent-check-reminder.sh`. Note that on exit 0 a UserPromptSubmit hook's stdout is injected
  into Claude's *context* (unlike PostToolUse's user-facing stdout), so such a hook must print only
  the structured additionalContext JSON (via `reminder_emit_prompt`) or nothing at all. PostToolUse(Bash): `reminder_post_bash_init <OPT_VAR>` (opt-out + INPUT/COMMAND;
  reads `.tool_input.command` on its own so a multi-line command isn't truncated), followed —
  after the hook's own command-shape match — by `reminder_cwd_session` (CWD/SESSION in one jq
  pass). The split is deliberate: these hooks run on *every* Bash tool call, so the second jq
  spawn isn't paid by a command the hook is about to ignore. **`reminder_cwd_session` is not
  optional** — SESSION is what makes a fire attributable to a repo (a session id resolves to
  `~/.claude/projects/<dir>/<session>.jsonl`), and `test_every_emitting_hook_establishes_a_session`
  in `tests/test_hook_sunset_bets.py` fails any hook that emits without it. Stop hooks: `reminder_opt_out <OPT_VAR>`, `reminder_stop_init <sentinel>`
  (INPUT/TRANSCRIPT/SESSION + the once-per-session sentinel guard; pass "" to skip the
  guard when the hook manages its own re-arm state), **`reminder_session_files`** (SESSION_FILES
  = porcelain + files committed since the session started — the gate any "did Claude work this
  session?" Stop hook wants, and the default over `reminder_changed_files`, because porcelain
  alone goes silent on exactly the commit-as-you-go sessions that do the most work), `reminder_session_added_lines`
  (this session's net added code lines in `$REPLY`: one diff from the last pre-session commit
  to the working tree, never a sum of per-commit patches, which counted every rewrite as
  growth; over `REMINDER_CODE_EXTS` — the growth signal,
  and the shared half of compress-comments-reminder's comment count),
  `reminder_code_globs`/`reminder_is_code_file`/`reminder_has_code_file` (the one
  code-extension list — a hand-rolled copy drifts),
  `reminder_transcript_invoked <sentinel> <needles…>` ($REPLY 0|1 — wraps the python
  `transcript_invoked`),
  `reminder_session_since` (session start as a `git log --since` argument in `$REPLY`, from
  the transcript's first-line timestamp; cached per session in `$TMPDIR`, so call it freely
  rather than threading the value through — and pass that value to python rather than
  having a heredoc re-derive it with `session_start`), `reminder_changed_files`
  (CHANGED from porcelain status), `reminder_state_file <name> [extra]` (per-session
  state path in $REPLY — existence for `reminder_fire_once`, a stored value for re-arming
  hooks), the re-arm trio
  `reminder_rearm_baseline`/`reminder_rearm_seed`/`reminder_rearm <name> <count> <threshold>`
  ($REPLY `first`/`growth`/`silent`, growth in `REMINDER_REARM_DELTA`), and
  `reminder_emit_stop <msg>` (`{"decision":"block","reason":…}` + exit 0 — Claude keeps working
  and acts on the reason in the same turn). **Never `continue: false` on Stop**: it halts Claude
  outright, and one halting hook overrides every blocking one; across every transcript since June
  only ~5 of ~1,050 such halts were acted on in-turn. `reminder_stop_init` exits silently when the
  payload's `stop_hook_active` is true, capping each natural stop at one forced continuation
  (`--when-active` opts out, for verify-work: the continuation is where Claude edits code, so it
  keeps verifying there, bounding its own blocks), and
  the re-arm baselines are keyed per session **and per repo** (an orchestrator's Stop fires from
  the main checkout and from worktrees alike).
  **Prefer a re-arming baseline over a once-per-session sentinel** for any "do this before you
  finish" hook. A sentinel fires once and then goes quiet however little that nudge got done;
  the fire log shows re-arming compress-comments-reminder averaging ~3.9 fires per session it
  speaks in against sentinel-era review-reminder's exactly 1.0. Cap the un-satisfied case
  (a nudge counter, or requiring growth) so Stop can still terminate.
  **Prompt/agent hooks (`"type": "prompt"`, `"type": "agent"`) are only available on tool
  events** — PreToolUse, PostToolUse, PermissionRequest. Not Stop, not UserPromptSubmit: one
  configured there is accepted and silently never runs, so a Stop-time "judge" has to be a
  command hook.
  Both kinds: `reminder_mktemp` (composable temp files — result in `$REPLY`, one shared
  cleanup trap; do NOT set your own `trap … EXIT`, it would clobber the lib's),
  `reminder_redact_secrets` (strip credential-shaped values from text before it is
  persisted — used on the prompt-log write path; vendor prefixes carry no leading `\b`
  on purpose, so a secret pasted with no space before it still matches),
  `reminder_is_frontend_file`,
  and `reminder_is_test_path`. Shared embedded-python helpers (`git()`, `is_test_path()`,
  `scan_script_dirs()` for the recursive script-index inventory, `authored_scripts()` for the
  save-script-reminder transcript scan, and `transcript_invoked()` for "did this skill/agent
  actually run?" — a tool_use walk, NEVER a bare-name transcript grep: the transcript's
  skill_listing attachment names every installed skill, so a plain grep for a skill name
  matches in every session and permanently suppresses the hook. Its `<command-name>` branch
  must match INSIDE the tag (`[^<>\n]{1,100}`), not "both substrings on the same line": a
  transcript line is often a whole API request, in which the Skill tool's schema documents
  the "`<command-name>` block" while the skill listing separately names the needle. An unbounded `.*?` is no better; it spans the docstring that documents the tag) live in `lib/hook_helpers.py` — import them by
  passing `"$SELF_DIR/lib"` as an argv:
  `sys.dont_write_bytecode = True; sys.path.insert(0, sys.argv[N]); from hook_helpers import git`.
  Extend the lib rather than copying a jq expression or helper into a hook; a hook whose
  copy drifts doesn't error, it silently sees empty content and never fires. The bash
  `reminder_is_test_path` and python `is_test_path` deliberately mirror each other — change
  both or neither.
- **Every emission goes through a `reminder_emit_*` helper** — that is where the opt-in fire
  telemetry (`DEV_HOOKS_FIRE_LOG`) is recorded, so a hook that hand-rolls its own jq, `echo`,
  or `printf >&2` never reaches `hook-fires.jsonl`, and its "0 fires" becomes undecidable for
  weekly-automation-review's Retire pass. Pick by loudness: `reminder_emit_note` (stdout +
  exit 0, shown to the user) < `reminder_emit`/`_session`/`_prompt` (additionalContext) <
  `reminder_emit_correction` (exit 2, fed back to Claude) and `reminder_emit_stop` (blocks the stop). `reminder_emit_decision`
  is its own thing (PreToolUse permission). `tests/test_hook_sunset_bets.py` gates all of it:
  every emit function in the lib must call `_reminder_log_fire`; every hook must call some
  `reminder_emit_*` or sit in that test's `SILENT_HOOKS` allowlist with a reason (only
  `lint-on-edit.sh` and `prompt-log.sh` qualify — they genuinely never speak).
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
