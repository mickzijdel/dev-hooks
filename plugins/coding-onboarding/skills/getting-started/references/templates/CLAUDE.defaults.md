# Working defaults

Standing instructions for working with me on any project. A specific project's own `CLAUDE.md`
can override these.

## Be thorough, not fast

You are not a human engineer. What would take a person days or weeks, you can do in hours — so
don't optimise for saving time or take shortcuts to finish quickly. Spend that speed on doing
the job properly: thorough fixes, real implementations, and actually verifying the result.

## Always Works — verify before you claim

"Should work" is not "does work". Untested code is a guess, not a solution. Before telling me
something works, every answer must be yes:

- Did you actually run/build the code?
- Did you exercise the exact thing you changed?
- Did you see the expected result with your own eyes (including the UI, if it's a UI change)?
- Did you check for errors in the output?

Match the test to the change: a UI change → click it; an API → call it; data → query it; logic →
run the scenario; config → restart and confirm it loads. Avoid "this should work now" / "try it"
unless you've tried it yourself. When you run tests, read the **full** output — don't tail or
head it, or you'll just have to rerun them to see the error.

## Plan before big changes

For anything beyond a small, obvious edit, propose a short plan first and let me look at it
before you start writing code. For genuinely large or unfamiliar tasks, use plan mode. (Being
fast is not a reason to skip this — a quick plan keeps a big change reviewable.)

## Keep changes small and committed

- Work in small, focused steps. Commit working pieces as you go.
- Make changes on a **branch**, not directly on `main`, and open a pull request when ready.
- Keep commits **atomic**: stage only the files for this specific change, never bundle
  unrelated edits. Make new commits rather than amending, unless I ask.
- Before committing, show `git status` and `git diff --staged`, stage only the relevant files,
  then commit.

## Don't lose or leak things

- **Never** write plaintext secret *values* into committed files (API keys, passwords, tokens).
  Use environment variables or a secrets manager, and keep `.env` / `.env.local` gitignored.
- Before any destructive command (deleting files, `git reset --hard`, force-pushing), stop and
  confirm with me — explain what it does and why.
- Never remove or refactor working functionality unless the task explicitly calls for it.

## Prefer the modern command-line tools

When they're installed, reach for the faster, clearer tools over the classic ones: `rg`
(ripgrep) instead of `grep`, `fd` instead of `find`, `bat` to show a file, `eza` to list a
folder, and `delta` for git diffs. They have saner defaults and respect `.gitignore`. Fall back
to the classic command if the modern one isn't available.

## How to explain things to me

<!-- getting-started replaces this section per references/explanation-levels.md, using the
     user's stated experience level (Step 2) and a date-stamped check-back-in footer. The text
     below is a safe default if it wasn't customized. -->

When you run something non-obvious, say in one line what it does and why. When a decision has real
trade-offs, give me the options briefly and recommend one. If a request is ambiguous, ask a short
clarifying question instead of guessing — a 10-second question beats redoing the work.
