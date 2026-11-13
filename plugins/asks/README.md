# asks

A Claude Code mod that answers one question: **what are my sessions waiting on me for?**

`/asks` opens a pane, in any session, that lists the ask of every local session that runs this
plugin. It shows one ask in full, with the context to decide, and lets you answer with one key
or in your own words. The answer goes to the session that asked.

Part of the [dev-hooks marketplace](../../README.md). It ships no skills and no command hooks,
only the mod, so it needs a Claude Code with mods and does nothing on one without. Its tests
run on 2.1.323, the version this repo's CI pins, and on 2.1.310.

## Installation

```bash
/plugin marketplace add mickzijdel/dev-hooks
/plugin install asks@dev-hooks
```

Install it once; every local session then loads it, and each session's ask reaches the pane.

## Usage

```console
$ claude
> /asks
```

The pane opens beside the conversation. Click in it once so the keys work, then answer the
ask in view: `y` or `n` for a go-ahead, a digit for a choice, `r` to answer in words.

## What an ask is

At the end of each turn the mod reads the reply's `**Your move:**` block with plain code. The
label must open a line, and a `Brief:` line is left out:

```markdown
**Your move:** Run the import migration on the rehearsal copy?
**Recommend:** Yes. This copy is not production.
**Blocks:** 2 more tasks

**Changed:** The migration script.

**Undo:** Easy. Drop the two columns.

Details (skippable)
…nothing below this line is read…
```

- No `**Your move:**` block leaves an earlier ask open. A move of "Nothing" closes it.
- A prompt you type in the session closes its ask. So does the session ending.
- An open `AskUserQuestion` dialog is listed too, to be answered in its own session.

The session's reply decides the shape of the memo:

| The move | Kind | You answer with |
|----------|------|-----------------|
| A yes-or-no question (`…?` that does not open with which, what, how… or offer "A or B"), or a `**Recommend:**` of yes or no | GO-AHEAD | `y` Yes, `n` No |
| A numbered list with a recommendation or a word such as "choose" | CHOOSE | `1`–`9` |
| A command in backticks to run | DO | `c` copy, `d` Done |
| A pull request link, or a `**Review:**` line | REVIEW | `o` open, `e` Seen |
| Anything else | ANSWER | `r` answer in words, `e` Seen |

`**Kind:**` (go-ahead, choose, do, review, reply) overrides the guess. Write an option as
`label — consequence` and the pane shows the consequence under the label. `**Blocks:**` sorts
the ask first and is drawn in coral; `**Risk:**`, `**Undo:**`, `**Changed:**`,
`**Not checked:**` and any other labelled line become fact rows under the answers.

## What the pane does

- **One memo, then a list.** Asks that block other work come first, then the oldest. The memo
  stays on the ask you are reading: a more urgent ask that arrives waits under "Also waiting".
- **Keys.** Each button shows its key; they work once the pane has the focus (click in it).
  `r` opens a field for another answer, `j`/`k` move between asks, `u` follows up on your last
  answer, `p` sends a new prompt to any session. While a field is open no button has a key.
- **A receipt.** After an answer the pane shows what was sent and the stated way to undo it,
  then moves to the next ask.

## What it runs, sends and stores

- **Sends as you.** A button sends a fixed text (`Yes, go ahead.`, `No.`, `done`,
  `Option N: <label>`) or the words you typed, followed by the session's own question so a late
  answer cannot be misread. It is submitted as your own prompt.
- **Between sessions.** Each session's copy of the mod keeps its ask, its presence and the
  messages for it in the plugin's store, one JSON file under your Claude Code config folder
  that every session reads. A session picks its messages up every 3 seconds. A message nobody
  picks up within 2 minutes is dropped and its ask put back, and the pane says "Not delivered".
- **One model call per ask.** A Haiku call, on the session's own connection, writes a subject
  line of at most nine words from the ask. Button labels and sent texts never come from a model.
- **Programs.** `grep` searches your Claude Code `projects` folder for this session's
  transcript, to read the title the app gave the session; it runs when a session starts and
  at the end of each turn. `open <url>` (`xdg-open` where there is no `open`) runs when you
  press Open on a review.

## Safety rules in the code

- A press answers only the ask that has been the memo for at least 0.6 seconds, so a double
  press cannot answer a question you did not read.
- Only a yes-or-no question, or a stated yes-or-no recommendation, gets a Yes button. An
  open question ("Which database?", "A or B?") and an instruction get an answer field.
- A numbered list of steps is not treated as a choice; its lines stay in view.
- Answers are never sent to an ask that changed underneath: the memo is pinned.

## Development

The pure half (`hooks/parse.ts`, `hooks/describe.ts`) reads replies; `hooks/register.tsx`
holds every `$` call and the drawing. The state contract is `types/index.d.ts`. Tests are
`tests/*.test.ts(x)`, run by `claude plugin test plugins/asks` (and by `tests/test_mods.py`).

## License

MIT, as the rest of the [dev-hooks marketplace](../../LICENSE).
