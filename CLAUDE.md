This repo is a multi-plugin marketplace monorepo: `.claude-plugin/marketplace.json` at the
root serves five plugins from `plugins/{dev-hooks,coding-onboarding,thinking-tools,writing,asks}/`,
each with its own `.claude-plugin/plugin.json`, `README.md`, and `skills/` (dev-hooks,
writing and thinking-tools also ship `hooks/` — see "Authoring hooks" below; asks ships only
a mod — see "The asks mod").
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
when both exist) and only stable one-line descriptions; don't re-add either.
`tests/test_marketplace.py` fails a description that names its plugin's skills, which drifts. The hk
`plugin-validate` step runs `claude plugin validate --strict` over the marketplace and every
plugin when plugin files are staged; CI runs the same validation through `tests/test_mods.py`
on the two plugins that ship a mod, dev-hooks and asks.

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
outside any repo), and the `classic.Stop` verdict. A skill is recorded from both `skill.prompt`
and the Skill `tool.call` (`recordSkill`, one entry when both arrive within 10 s): a plugin
seated above can send `skill.prompt` past the module, and a slash command makes no Skill call.
`tests/test_mod_bypass_live.py` (opt-in, `DEV_HOOKS_LIVE=1`, a real `claude -p` run) fails when
an event outside its `KNOWN` list is sent past the module. Rules learned building it:
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

The module **orchestrates the Stop hooks**: its `classic.Stop` hook sets `DEV_HOOKS_MOD_SESSION`
to the session id before it calls `next` (`markStopTakenOver`; `$.env.set` reaches every command
hook started afterwards), which makes `reminder_stop_init` exit for the direct runs. The mark is
made there and never in `session.start`, so it exists only where that hook runs: a plugin seated
above can send `classic.*` past the module (the built-in `cc-plugin-sec-default` does in a team
organization; Claude Code then logs "its classic.Stop hook was skipped"), and the command hooks
must keep running there. The mark is proof for one Stop only: `turn.start` (which does reach the
module there) clears it on every main-loop turn (`clearStopMark`), so a later Stop that is sent
past the module, or a session an older version marked at session start, finds the command hooks
running. Untested, since this module's `classic.Stop` can't run on a team-organization machine:
that the `$.env.set` made before `next(e)` reaches the command hooks that same `next(e)` starts
(if it doesn't, each Stop runs every hook twice), covered only by the call order in
`tests/stop-takeover.test.ts`. The hook then runs each Stop
command from `hooks.json` itself via `$.process.run` with `DEV_HOOKS_ORCHESTRATED=1`, parses each
answer the way Claude Code does (`stopReason`) and returns one merged `block`, closed once by
the end-report footer (`mergeBlocks`; none when headless). It writes the
session facts to `$TMPDIR/dev-hooks-facts-<session>.json` first and passes the path as
`DEV_HOOKS_FACTS_FILE`, so a Stop hook asking "did X run?" goes through
`reminder_transcript_invoked` and gets subagent-aware answers for free. If orchestration throws, the
module unsets the marker (the command hooks take Stop back from the next turn) and records the
plugin version under `stopOrchestrationFailed` in `$.store`; the hook won't mark a
session on that version again, so only a version bump re-enables it. Every `--plugin-dir`
copy named `dev-hooks` shares one inline store (`dev-hooks_inline-*.json`), separate from the
marketplace install's — clear that key after fault-injection tests. So a new dev-hooks
Stop hook must go through `reminder_stop_init` (`test_every_dev_hooks_stop_hook_goes_through_reminder_stop_init`
enforces it) — one that doesn't would run twice. Don't stand hooks down by skipping `next` in
`classic.Stop`: that silences every Stop hook beneath the module, other plugins' and the user's too.

The module also routes **the guard's questions to the person**: its `classic.PreToolUse` hook
takes a decision whose `ask` starts with `GUARD_PREFIX` (`dev-hooks guard — `, pinned on both
sides by `test_guard_prefix_matches_the_mod`) from any tool (`private-email-guard.sh` asks about
WebFetch, file writes and MCP calls; `guardSubject` names a non-Bash call as tool + target, and
keys a late Allow by it; an email ask's addresses, listed after `EMAIL_ASK_MARK` and pinned by
`test_email_ask_marker_matches_the_mod`, get an "Allow for this session" button whose answer is kept
in `$.state` `emailsAllowedTo`, keyed by the destination the hook names after `DEST_MARK` (read by `askedDestination`) so an address approved for one service can't
reach another unasked; no destination, no button) and asks via `$.ui.ask`, which reaches the person
even in auto mode (probed 2026-10-03; a plain PreToolUse `ask` is answered by the classifier).
Allow returns the decision **minus** its `ask` — never `allow`, so the user's own permission
rules still run; Deny, a dismissal and a timeout all refuse. The wait is the command's own
leading `DEV_HOOKS_GUARD_DIALOG_TIMEOUT=N` (`commandTimeout`; Claude may set it — a timeout only
refuses), else the session env, else 120 s. In a team organization this hook never runs (the
built-in `cc-plugin-sec-default` sends `classic.*` past user mods) and the guard's `ask` goes to
Claude Code's own permission prompt; `tool.check` is no way round it, since a user-tier hook
there may only tighten a verdict (`plans/off-topic-improvements.md` has the probe results).
A `$.ui.ask` can't be closed from the mod, so a timed-out dialog lingers, and the VS Code extension
doesn't draw it through `ui.render` (the `guardTimedOut` redraw only helps surfaces that do). What
works everywhere is the late answer: the abandoned `ask` promise still resolves, and
`lateGuardAnswer` submits it to Claude, a late Allow also granting that exact command one
ask-free run within 10 minutes (`lateAllowed`, module memory — a reload drops it). Note that
`$.env.set` reaches *every* process Claude Code starts afterwards, nested `claude -p` runs
included — only ever set variables that are inert outside this session or keyed to its id.

The module also tracks **Stop-nudge outcomes** (`hooks/nudge-outcomes.ts`, pure; `$` stays in
`register.tsx`'s `trackNudges`/`closeNudges`/`sweepNudges`/`logNudges`). Each reason the
orchestration returns is a `Nudge` in the session's facts, named by its script (`hookName`), not
its tag. The next orchestrated Stop — normally the continuation the block forced — resolves the
pending ones with `resolveNudge`, one remedy per hook from facts recorded after the fire
(`lastEdit` gives per-file edit times); `session.end` and, for sessions idle 6h+, the next
`session.start` resolve leftovers as `unknown` unless evidence says acted. Resolved nudges go to
`nudgeOutcomes` in `$.store` (union by session+hook+time, 90 days, 3,000 max) and are exported
to `~/.claude/automation-review/stop-nudges.json` when that directory exists — the file the
automation-review skill reads. A new Stop hook gets `unknown` until it has a case in
`resolveNudge`; give it one only for a remedy the facts can show. A probe session
(`isProbeSession`) adds no nudges at all, so its facts give session end and the sweep nothing
to log; `$.classic` is undefined under `claude plugin test`, so that gate is verified with a
live `claude -p --plugin-dir` run. Such a run's mod keeps the inline store, and every copy merges
its records into the one export (`exportedRecords`) rather than replacing it: `$.plugin` carries
only `name` and `root`, and the marketplace install's root is this working copy, so no copy can
tell which one it is. The review needles, the memory-dir and skill-queue regexes and the probe rule are mirrors of
`review-reminder.sh`, `hook_helpers.MEMORY_DIR_RE`/`SKILL_QUEUE_RE`/`SKILL_QUEUE_WRITE_RE` and `reminder_is_probe_session`,
pinned by `tests/test_nudge_parity.py`. The facts' `bashNamed` (the CI-watch Bash hook records a
redirect or `tee` into the skill-candidate queue, never a read) is the one Bash-made remedy the nudges see.

The module **watches CI after a push** (the `CI watch` block of `register.tsx`; its pure half —
push detection, push-output parsing, run verdicts, the texts — is `hooks/ci-watch.ts`, imported
and unit-tested directly). A `tool.call` hook on `{ tool: 'Bash' }` runs after `next(e)`, reads
the pushed commits from git's push output in the tool result's `text` (stderr is in it), adds a
`context` note to that result, and chains `$.clock.after` polls of `gh run list --commit <sha>`
outside the dispatch (a timer's closure keeps using the hook's `$`). Elapsed time comes from
`$.clock.now()`, not `Date.now()`, so `mock.clock` drives it in tests. The outcome reaches Claude
two ways, both verified live: `$.session.append` (a user-role note, read at the running turn's
next request, starting no turn) for a pass, and `$.prompt.submit` (queued until idle, then a turn
of its own, even under `claude -p`) for a failure. With the desktop app's Auto-fix on, a
failure on a commit that heads an open PR goes the append way first, since Auto-fix starts that
turn itself: the `prompt.submit` hook records in `$.state` (`autoFixSeen`) what each
`<ci-monitor-event>` opens with (`autoFixEvent`: the `owner/repo#N` it reports on, or `*` for
"was just enabled", anchored at the start so a quoted event says nothing, and only from an `sdk`
or `auto-continuation` origin, which is how transcripts record the app's events, so another
session's message or a notification never counts; a prompt typed in an SDK host may still
arrive as `sdk`), and the watch asks
`gh api repos/<repo>/commits/<sha>/pulls` which open PR has the commit as its head
(`parseHeadPrs`). The stand-down is a deferral, never a drop: `AUTO_FIX_GRACE_MS` after the note,
`wakeIfAutoFixSilent` submits the failure as a prompt unless an Auto-fix event named that PR
since the push, and marks the PR silent (`-1`) so its later failures wake the session at once
until an event names it again. The fallback is a `$.clock.after` timer like the polls, so a
reload inside the 10 minutes leaves only the note. Not verified live: that the desktop app's
events raise `prompt.submit` with those origins.
`session.start` sets
`DEV_HOOKS_CI_WATCH_SESSION`, which `ci-watch-reminder.sh` matches against its session id to stand
down — a separate marker from `DEV_HOOKS_MOD_SESSION`, which a failed Stop orchestration clears.
In `claude plugin test`, `mock.session(on)` (Claude Code 2.1.293+) records the plugin's own
`$.session.append` calls; `tests/ci-watch-hook.test.ts` reads them back with `.appended()` to tell
the append path from the prompt path.

The module also draws **the session-status pane** (the `Session-status pane` block of
`register.tsx`; its pure half, the end-report and brief parsers and the state derivation, is
`hooks/status-pane.ts`, unit-tested directly). It records each main-loop turn (`turn.start`,
`turn.complete` with the final message's parsed end report), tool and edit counts per turn, this
session's commits and pushes from Bash output (`gitDir` in `ci-watch.ts` finds the repo, by its
main checkout's name), and the Stop input's `background_tasks` and `session_crons`, all in one
`$.state` value written through the `changePane` queue (tool calls run in parallel). The value is
stored as `{ shape, value }`; change `PANE_SHAPE` when `StatusPaneState` changes shape, so an older
value is declined rather than misread. The view reads every turn since the last typed prompt
(`typedFrom`: the origin `prompt.submit` names before `turn.start`, `composer`, `bridge` or `sdk`;
the text only when no origin arrived), so a notification or scheduled turn can't clear an earlier
ask, and a later turn's report covers an earlier one that left none (a Stop hook's continuation
is a turn of its own). It stores a line of each answer (`answerFacts`), never the answer: the
value is read and written on every tool call. Rules learned building it:
the engine skips a render hook whose tree holds a `Button` without `onPress`; pane tests mount on
`terminal` and `vscode` and answer `state.get` with a reader (one `on` per event); the mod runtime
has no `setTimeout` in its types, and `ui.press` awaits a handler that returns its promise. Its
label patterns mirror `hook_helpers.end_report_missing`'s, pinned by
`tests/test_status_pane_parity.py`. Design and plan: `docs/superpowers/specs/2026-10-25-status-pane-design.md`.

## The asks mod (`plugins/asks/hooks/register.tsx`)

A plugin of its own, with no skills and no command hooks: `/asks` opens a pane that lists what
every local session is waiting on the person for. Each session's copy parses its reply's
`**Your move:**` block at `turn.complete` (`hooks/parse.ts`), and `hooks/describe.ts` derives
the memo's kind, question, options and fact rows from it by plain code; both are pure and
unit-tested directly, and `$` stays in `register.tsx`. Its tests are `plugins/asks/tests/`,
run by `tests/test_mods.py`. It installs without dev-hooks, so it shares no code with the
session-status pane, which reads the same end report for one session. Rules learned building it:
- `$.store` is one file for every session of the plugin, which is what makes the pane
  cross-session. Keys: `ask:<session>`, `here:<session>` (presence), and one
  `send:<session>:<time>-<n>` per message for a session, read by that session's 3-second poll.
  A message unread after `UNREAD_MS` is dropped by any session's `refresh` and its ask put
  back; `deliver` leaves such a message alone, so the drop and the restore stay in one place.
- It uses the `atom`/`read`/`update` state helpers, which `claude plugin validate --strict`
  accepts on 2.1.310 and later when the atom is a const of the file, passed by name (a helper
  that takes the atom as a parameter is refused).
- `sessionLabel` greps the whole `projects` folder for the session's `customTitle` rows, so it
  runs at session start and at the end of a turn only; `knownLabel` serves the rest from
  module memory.
- The memo is pinned (`pinned`, module memory) and a press answers only an ask that has been
  the memo for `GUARD_MS` (`isRead`): the list is re-sorted on every poll, and without both a
  key press could answer an ask the person never read. Keep every answering path behind `answer`
  or `seen`.
- The text a button sends is fixed in `SENDS`, never model-written, and is submitted
  `asUser`; `answerText` appends the session's own question. The one model call (`addTopic`)
  writes only the subject line.
- The desktop draws each Button's `hotkey` as a chip beside the label, so labels carry no key;
  a Box one cell high is a thick bar there, so the pane uses no separator Boxes. While an
  Input is open (`mode` other than `view`) no Button gets a `hotkey`.
- A hot reload runs new code only from the next turn: a reply's ask is recorded by the code
  that was loaded when the turn ended, so a parser change shows one reply late.

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
- **A new or changed description ships with a headless trigger probe**, run from an empty
  scratch dir (the turn cap and the dir keep the probe from doing the task in the repo):
  `DEV_HOOKS_PROBE=1 claude -p --no-session-persistence --max-turns 3 --plugin-dir <abs path>/plugins/<plugin> --output-format stream-json --verbose "<realistic prompt>" | jq -rc 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Skill") | .input.skill'`.
  Run it for should-fire and should-not-fire prompts (no output = no skill picked); exit 1
  only means the turn cap ended the run.

## Authoring hooks (`plugins/dev-hooks/hooks/scripts/*.sh`)

- **The standalone-plugin hooks never source dev-hooks' lib.** The `writing` plugin
  (`readme-reminder.sh`, the four `voice-*.sh`) and the `thinking-tools` plugin
  (`thinking-tools-reminder.sh`) live in their own
  `plugins/*/hooks/` and must NOT source `reminder-common.sh` or import `hook_helpers.py`:
  those plugins install without `dev-hooks`, and a cross-plugin `source` would break that
  standalone install. Sharing *within* a plugin is fine and preferred — the writing hooks
  ship together, so they share `plugins/writing/hooks/scripts/lib/voice-common.sh`
  (`voice_opt_out [VAR]`, `voice_payload`/`voice_field`, `voice_prompt_typed`, `voice_profile`,
  `VOICE_PROSE_EXTS` + `voice_is_prose_file`, `voice_transcript_scan`,
  `voice_state_file`/`voice_fire_once`, `voice_emit <event> <msg>`, `voice_emit_stop`, and
  the `DEV_HOOKS_FIRE_LOG` telemetry those emits record). `VOICE_PROSE_EXTS` is passed into
  `voice_transcript_scan`'s python heredoc by argv rather than re-listed there — a drifted
  copy of an extension list doesn't error, it just silently stops seeing files.
  `thinking-tools`' one hook has no sibling to share with, so its small reimplemented bits
  stay terse and under jscpd's minTokens.
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
  PreToolUse(Bash): `reminder_pre_init <OPT_VAR> [jq-filter]` (opt-out + COMMAND/CWD/SESSION;
  reads `.tool_input.command` on its own so a multi-line command isn't truncated; the filter
  reads another tool's text instead, as `comment-brief-guard.sh` does for Agent/SendMessage) and
  `reminder_emit_decision <deny|ask> <reason>` (emit the `permissionDecision` JSON + exit 0 —
  never emit `allow`, which would bypass the user's own allowlist; stay silent for safe commands
  so the normal permission flow proceeds). UserPromptSubmit: `reminder_prompt_init <OPT_VAR>`
  (opt-out + INPUT/PROMPT/CWD/SESSION; reads `.prompt` on its own so a multi-line prompt isn't
  truncated — shares the `reminder_cwd_session` tail with `reminder_pre_init`) and
  `reminder_emit_prompt <msg>` (advisory additionalContext + exit 0), used by both `prompt-log.sh`
  and `intent-check-reminder.sh`. A hook keyed on what was asked reads `reminder_prompt_typed`
  (`$REPLY`: the words the person typed, empty for a task notification, subagent hand-back or
  CI-watch prompt, with IDE context, pasted blocks and a forwarded side-agent note's quoted lines
  stripped; cross-session messages stay, as they relay briefs), as `data-before-design-reminder`
  does: a subagent's report matched its cues 48 times in one week, and a false fire also spends
  the once-per-session nudge. The filter is copied into `voice-common.sh`, pinned by
  `test_typed_prompt_filters_match`. Note that on exit 0 a UserPromptSubmit hook's stdout is injected
  into Claude's *context* (unlike PostToolUse's user-facing stdout), so such a hook must print only
  the structured additionalContext JSON (via `reminder_emit_prompt`) or nothing at all. PostToolUse(Bash): `reminder_post_bash_init <OPT_VAR>` (opt-out + INPUT/COMMAND;
  reads `.tool_input.command` on its own so a multi-line command isn't truncated), followed —
  after the hook's own command-shape match — by `reminder_cwd_session` (CWD/SESSION in one jq
  pass). The split is deliberate: these hooks run on *every* Bash tool call, so the second jq
  spawn isn't paid by a command the hook is about to ignore. A hook that judges the *result*
  (`sfw-alert-reminder.sh`) also registers on PostToolUseFailure(Bash), since a non-zero exit
  arrives there with the output in `.error`, and answers via `reminder_emit <msg> <event>`.
  **`reminder_cwd_session` is not
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
  `reminder_transcript_invoked [--since <epoch>] <sentinel> <needles…>` ($REPLY 0|1 — wraps the python
  `transcript_invoked`, and also the mod's session facts via `facts_invoked` when
  `DEV_HOOKS_FACTS_FILE` is set, which see skills and agents run inside subagents),
  `reminder_runs_git <sub> [operand]` (does $COMMAND run `git <sub>`, as `git push` or `git worktree
  add`? Read from `shell-segments.awk`'s
  segments via `seg_parse`/`seg_git_sub`, now in the lib, so text that only mentions it doesn't
  count; never grep the raw command for a subcommand),
  `reminder_git_target_dir <words…>` (the directory the first `git <words…>` in $COMMAND runs
  in — following `cd` segments and `-C` — in `$REPLY`; use it, never `$CWD`, for "the repo this
  git command acts on", since `cd other && git commit` acts on `other`),
  `reminder_session_since` (session start as a `git log --since` argument in `$REPLY`, from
  the transcript's first-line timestamp; cached per session in the state dir, so call it freely
  rather than threading the value through — and pass that value to python rather than
  having a heredoc re-derive it with `session_start`), `reminder_changed_files`
  (CHANGED from porcelain status), `reminder_state_file <name> [extra]` (per-session
  state path in $REPLY — existence for `reminder_fire_once`, a stored value for re-arming
  hooks; under `$XDG_STATE_HOME/dev-hooks`, never `$TMPDIR`, because a resumed session outlives
  the reboot that empties it; conftest gives each test its own `XDG_STATE_HOME`), the re-arm trio
  `reminder_rearm_baseline`/`reminder_rearm_seed`/`reminder_rearm <name> <count> <threshold>`
  ($REPLY `first`/`growth`/`silent`, growth in `REMINDER_REARM_DELTA`), and
  `reminder_emit_stop <msg>` (`{"decision":"block","reason":…}` + exit 0 — Claude keeps working
  and acts on the reason in the same turn). It appends `REMINDER_END_REPORT_FOOTER`: the reply
  to a Stop hook becomes the last message the person reads, so the footer asks for the end
  report again, with the hook's own work as lines in it, or for one line when that work changed
  nothing in it (Mick, 2026-10-29: identical reports after every block read as the same message
  over and over; end-report-reminder passes a one-line reply after this turn's report,
  `hook_helpers.turn_reported`). Left off under orchestration (the mod
  adds it once) and in a headless run (`reminder_is_headless`: `CLAUDE_CODE_ENTRYPOINT`
  `sdk-*`, i.e. `claude -p` or the Agent SDK, or a nested run); copied into `voice-common.sh` and
  `register.tsx`, pinned by `test_end_report_footers_match`. **Never `continue: false` on Stop**: it halts Claude
  outright, and one halting hook overrides every blocking one; across every transcript since June
  only ~5 of ~1,050 such halts were acted on in-turn. `reminder_stop_init` exits silently when the
  payload's `stop_hook_active` is true, capping each natural stop at one forced continuation
  (`--when-active` opts out, for verify-work: the continuation is where Claude edits code, so it
  keeps verifying there, bounding its own blocks and skipping a failure the last block already
  reported unchanged), and
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
  command hook. `tests/test_hooks_json.py` fails any plugin's hooks.json that tries.
  Both kinds: `reminder_mktemp` (composable temp files — result in `$REPLY`, one shared
  cleanup trap; do NOT set your own `trap … EXIT`, it would clobber the lib's),
  `reminder_is_probe_session` (a made-up session id, a `/tmp/claude-*` scratchpad or
  `~/.cache/` cwd, `DEV_HOOKS_PROBE` set, or a nested run: the fire log and prompt log skip
  these; `_voice_log_fire` and the mod's `isProbeSession` mirror it),
  `reminder_is_nested_run` (a `claude` started from another session's shell, as a fan-out
  script does: it inherits that session's `CLAUDE_CODE_ENTRYPOINT`, and Claude Code gives
  every hook `CLAUDE_CODE_CHILD_SESSION`, so only the claude process's own environment,
  `/proc/$CLAUDE_PID/environ` (on macOS, `ps eww`), tells; the mod reads the same through `$.env`; also empties
  `reminder_prompt_typed`, silences `intent-check-reminder` (which reads the raw prompt) and
  counts as headless; copied as `voice_is_nested_run`, pinned by
  `test_nested_run_checks_match`),
  `reminder_redact_secrets` (strip credential-shaped values from text before it is
  persisted — used on the prompt-log write path; vendor prefixes carry no leading `\b`
  on purpose, so a secret pasted with no space before it still matches),
  `reminder_is_frontend_file`,
  and `reminder_is_test_path`. Shared embedded-python helpers (`git()`, `is_test_path()`,
  `scan_script_dirs()` for the recursive script-index inventory, `memory_written()` for "did this
  session write a memory file?" (transcript Write/Edit into a memory dir, plus the facts file;
  `path_written()` is the same check for any path regex, plus an optional command regex for a
  Bash append, as skill-candidate-reminder uses for its queue), `human_turns()` for the "substantial session" turn count with the sentinel guard, `authored_scripts()` for the
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
  automation-review's Retire pass. Pick by loudness: `reminder_emit_note` (stdout +
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
  `shellcheck **/*.sh`, `ruff check . && ruff format --check .`, and
  `bash scripts/run-jscpd.sh python,bash`. Ruff targets Python 3.12 (`pyproject.toml`), the
  floor the shipped scripts declare and `hook_helpers.py` must import under. ruff runs its
  default rule set (minus `UP031`, and `PLW1510` in tests), pinned to one minor in both
  `mise.toml` and the uv dev group, and `ruff format` also covers the Python blocks in `*.md`:
  keep a deliberately bad example between `<!-- fmt: off -->` and `<!-- fmt: on -->`, and
  annotate a deliberate catch-all `# noqa: BLE001 - <reason>`. Let `shfmt -w` do the
  formatting — with `.editorconfig` it rewrites `case` patterns to `a | b)` and pushes `$(…)`
  heredocs onto their own line.
