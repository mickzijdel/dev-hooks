# writing

A Claude Code plugin of writing/content skills.

Part of the [dev-hooks marketplace](../../README.md), alongside `dev-hooks`,
`coding-onboarding`, and `thinking-tools`.

## Skills

| Skill | Use when |
|-------|----------|
| `github-readme` | Creating/revising a GitHub README — section order, onboarding flow, runnable quickstart, plus an audit script and advanced GFM features. |
| `humanizer` | Removing tells of AI-generated writing — em-dash overuse, rule-of-three, promotional tone, etc. (based on Wikipedia's "Signs of AI writing"). |
| `readability` | Making web copy scannable — inverted pyramid, plain language, plus Flesch-Kincaid/vocabulary audit scripts. |

> `github-readme`, `humanizer`, and `readability` are adapted **verbatim** from
> [Nate Berkopec's dotfiles](https://github.com/nateberkopec/dotfiles) (credit to Nate; each
> `SKILL.md` links back to its source). `humanizer` is additionally based on
> [Wikipedia: Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing)
> (WikiProject AI Cleanup).

## Install

```bash
/plugin marketplace add mickzijdel/dev-hooks
/plugin install writing@dev-hooks
```

## Notes

- The `github-readme` and `readability` skills bundle optional Python audit scripts
  (`scripts/*.py`, self-contained via [uv](https://docs.astral.sh/uv/) + PEP 723 inline
  metadata — run with `uv run scripts/<name>.py`); they only run when you invoke the skill
  and ask for the audit.
