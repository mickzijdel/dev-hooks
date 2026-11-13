---
name: one-fix
description: Use when several bugs, review findings or edge cases look related and are about to be patched one by one, when a fix adds the same check in a second place or a third special case, before wrapping up a diff or PR, or on "one fix for all of these", "find the root fix", "stop patching edge cases", "why do we keep fixing this". Takes a diff, a PR or the whole repo. Not for one isolated bug (systematic-debugging) or module depth (codebase-design).
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Agent
  - Edit
  - Write
---

# one-fix

Replace a batch of point fixes with **one change that makes the whole class impossible**.
Per group of related fixes, the question is: *what single rule, enforced in one place,
makes all of these unreachable?*

**You gather the evidence yourself.** Never ask the person for commits, findings or file
lists that `git`, `gh` and `rg` can give you.

## Tripwires

Stop patching and run this skill when any of these is true of the work in hand:

- the same guard is about to exist in two places
- a third conditional is going in for what is one bug
- the fix is a fix to an earlier fix
- the "search the codebase for the same mistake" pass returned two or more hits

## Steps

1. **Pick the scope** from what was asked; default to the diff. The inventory covers
   source files only: drop manifests, lockfiles, changelogs, docs and tests from the
   file list.

   - **diff** (default):

     ```bash
     base=$(git merge-base "$(git symbolic-ref -q --short refs/remotes/origin/HEAD || echo main)" HEAD); git diff --name-only "$base"; git status --porcelain
     ```

     When `$base` is HEAD (you are on the default branch), the range is this session's
     commits.
   - **PR** `<n>`: `gh pr diff <n> --name-only` for the files; `gh pr view <n> --comments`
     and `gh api --paginate repos/{owner}/{repo}/pulls/<n>/comments` for the review
     findings.
   - **repo**: the source files that fix commits touch most, or the area the person
     named.

     ```bash
     git log --since='12 months ago' --format='@%s' --name-only | awk '/^@/ { fix = tolower($0) ~ /^@(fix|revert)/; next } fix && NF' | sort | uniq -c | sort -rn | while read -r n f; do [ -f "$f" ] && echo "$n $f"; done | head -30
     ```

     Take the source files fixed three or more times. If the repo's subjects do not
     start with `fix`, drop the `fix &&` condition and take the most-changed files.

2. **Collect the fix history**, newest five per file in scope:

   ```bash
   for f in <files>; do git log -5 --format='%h %s' -i -E --grep='^(fix|revert)|workaround|regress' -- "$f"; done | sort -u
   ```

   Read those diffs (`git show <hash> -- <files>`). Findings already in hand (a review, a
   bug list, the same-mistake search hits) join the evidence as they are.
3. **Dispatch one subagent** with the brief below, filled in.
4. **Check each proposal against the code** before passing it on. For a guard it says
   can go: open the line and confirm the stated path into it is closed by the change.
   For copies it says can merge: open each copy and confirm every difference between
   them is either accidental or kept by the merged version. Drop what you cannot
   confirm; drop a proposal that no longer replaces at least two rows.
5. **Act or report.** Make the change, delete what it replaces and run the tests only
   when all three hold:
   - the place to enforce the rule and every line it removes are in the diff
   - the diff is your own work on the branch that is checked out
   - the proposal lists no behaviour change for callers

   Otherwise report the proposal and change nothing. Repo scope always reports.

Done when every row of the inventory names its group (or is marked a singleton), every
group of two or more has either a proposal or a stated reason there is none, and every
line a proposal removes carries its argument: the path that used to reach it and where
that path now stops, or the copy that now serves its callers.

## The subagent brief

Dispatch with `subagent_type: "general-purpose"`. Copy this, filling the brackets.

```
You are looking for ONE change that replaces MANY point fixes. Do not list bugs and do
not review style.

REPO: [absolute path]
SCOPE: [diff | PR n | repo] — [the files]
EVIDENCE: [the diff or file list, the fix commits with hashes, any findings in hand]
MOVES: read [absolute path of this skill's references/moves.md, under $CLAUDE_PLUGIN_ROOT/skills/one-fix/] first.

METHOD
1. Inventory. One row for every guard, special case, fallback, normalisation and earlier
   fix in the scope's changed lines and in the fix commits: file:line, the bad input or
   state it defends against, where that input or state comes from. The commits are a
   starting sample: read the code around each one, where the older defences sit.
2. Siblings. For each row, search the whole repo (rg) for the same defence, and for the
   same unguarded operation, outside the scope. Each hit is a row too, marked "outside
   scope".
3. Group the rows by the invariant they protect — the one sentence that, if always true
   at that point, would make the row unnecessary. Rows that defend against the same
   origin belong together even when the code looks different. Rows that only look alike
   but change for different reasons stay apart. A row alone is a singleton; say so.
4. For each group of two or more rows, look for the single place every path passes
   through, or the type or schema that could not hold the bad value. Name the move from
   moves.md.
5. For each row the change replaces, give the argument: either the path that reaches the
   guard today and where the change stops that path, or the shared copy its callers
   would use and why the differences between the copies do not matter. No argument, no
   removal.

HARD RULES
- "No single fix exists for this group" is a correct answer. Say why (two origins, no
  shared chokepoint, an external contract) rather than inventing an abstraction.
- A proposal must leave fewer copies of the rule than it found. Moving one check from
  one place to another is not a fix.
- Change nothing. Propose only.

REPORT BACK
- per group of two or more, strongest first: the invariant in one sentence; the one
  place to enforce it; the move; each line it removes with its argument; what the change
  does NOT cover; any behaviour that changes for callers; any new coupling it creates;
  the one test at that place that replaces the per-case tests
- groups with no single fix, and why
- the inventory table, a group or "singleton" on every row
```

## Reporting

Lead with the strongest proposal: the invariant, the place, and the lines it removes.
Then the groups with no single fix. The inventory table goes last.
