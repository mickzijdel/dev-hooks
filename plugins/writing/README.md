# writing

A Claude Code plugin of writing/content skills, plus hooks that audit READMEs, nudge you to
apply your voice profile before writing, and check prose against that profile on write.

Part of the [dev-hooks marketplace](../../README.md), alongside `dev-hooks`,
`coding-onboarding`, and `thinking-tools`.

## Skills

| Skill | Use when |
|-------|----------|
| `github-readme` | Creating/revising a GitHub README — section order, onboarding flow, runnable quickstart, plus an audit script and advanced GFM features. |
| `humanizer` | Removing tells of AI-generated writing — em-dash overuse, rule-of-three, promotional tone, etc. (based on Wikipedia's "Signs of AI writing"). |
| `readability` | Making web copy scannable — inverted pyramid, plain language, plus Flesch-Kincaid/vocabulary audit scripts. |
| `voice-profile` | Matching a person's writing voice — apply a profile of their own rules (Do/Don't/banned words/before-after), build one from their samples, or fall back to baseline expository discipline. Bundles a `voice_audit.py` banned-word scanner. |

> `github-readme`, `humanizer`, and `readability` are adapted **verbatim** from
> [Nate Berkopec's dotfiles](https://github.com/nateberkopec/dotfiles) (credit to Nate; each
> `SKILL.md` links back to its source). `humanizer` is additionally based on
> [Wikipedia: Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing)
> (WikiProject AI Cleanup). `voice-profile` is original to this plugin.

## Hooks

| Hook | Fires on | Opt out |
|------|----------|---------|
| `readme-reminder` | A `Write`/`Edit`/`MultiEdit` of a `README*` (any case/extension) — runs the `github-readme` audit script on the file and feeds the results back, with a nudge to use the `github-readme` skill. Advisory only; never blocks the write. | `WRITING_README=false` |
| `voice-intent-reminder` | A `UserPromptSubmit` whose prompt reads as a writing/copy task **when a voice profile is discoverable** — nudges Claude to apply the `voice-profile` skill *before* drafting, so your voice is baked into the first draft. Fires once per session; silent without a profile. | `WRITING_VOICE=false` |
| `voice-reminder` | A `Write`/`Edit`/`MultiEdit` of a prose file (`.md`/`.mdx`/`.markdown`/`.tex`/`.txt`/`.html`/`.htm`/`.xhtml`) **when a voice profile is discoverable** — scans it with `voice_audit.py` and nudges toward the `voice-profile` skill if banned words appear. Silent without a profile or on clean prose; never blocks. | `WRITING_VOICE=false` |

## Install

```bash
/plugin marketplace add mickzijdel/dev-hooks
/plugin install writing@dev-hooks
```

## Usage

Invoke a skill by name, or let the hooks nudge you automatically as you write prose and
READMEs:

```console
$ claude
> /writing:humanizer      strip AI tells from a draft
> /writing:readability    make web copy scannable
> /writing:voice-profile  match a saved writing voice
```

## Notes

- The `github-readme`, `readability`, and `voice-profile` skills bundle optional Python audit
  scripts (`scripts/*.py`, self-contained via [uv](https://docs.astral.sh/uv/) + PEP 723 inline
  metadata — run with `uv run scripts/<name>.py`); they only run when you invoke the skill
  and ask for the audit.
- The `voice-reminder` hook discovers a profile from `$WRITING_VOICE_PROFILE`, then
  `<repo>/.claude/voice_profile.md`, then `~/.claude/voice_profile.md` (first hit wins). With a
  profile in place it runs `skills/voice-profile/scripts/voice_audit.py` on every prose write and
  nudges only when banned words appear. Point `WRITING_VOICE_AUDIT_SCRIPT` at another scanner to
  override the path; set `WRITING_VOICE=false` to silence the hook entirely. The
  `voice-intent-reminder` hook uses the same discovery order and the same `WRITING_VOICE`
  switch; it fires once per session on a writing-flavoured prompt to nudge Claude to apply the
  profile *before* drafting.
- The `readme-reminder` hook also runs `github-readme`'s audit automatically: on every
  README write it shells out to `skills/github-readme/scripts/github_readme_audit.py` with
  `python3` (the script is stdlib-only, so no `uv` needed). If that script can't be found or
  `python3` is missing it falls back to a once-per-session nudge. Point
  `WRITING_README_AUDIT_SCRIPT` at another checker to override the path; set
  `WRITING_README=false` to silence the hook entirely.

## License

[MIT](../../LICENSE)
