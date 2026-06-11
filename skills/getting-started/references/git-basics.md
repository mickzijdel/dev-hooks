# Git, for someone who's never used it

Git is how code is saved, versioned, and shared. If you've used "track changes" in a document
or save-points in a game, you already have the idea: Git remembers every version of your
project, lets you go back, and lets several people work on the same thing without overwriting
each other.

You don't need to memorise this. Claude runs most Git commands for you — this is so you
recognise what's happening and can ask for it by name.

## The words

- **Repository (repo)** — a project folder that Git is tracking. "Initialise a repo" =
  start tracking this folder.
- **Commit** — one saved version, with a short message describing what changed ("add login
  page"). A project is a chain of commits — its history.
- **Branch** — a parallel line of work. `main` is the trusted version. You make a new branch
  to try something, and merge it back into `main` when it works. If it breaks, you just throw
  the branch away — `main` is untouched.
- **Remote** — a copy of the repo somewhere else, usually on **GitHub**, so it's backed up and
  others can see it. `origin` is the default name for your GitHub copy.
- **Clone** — download a repo from GitHub to your machine.
- **Push / pull** — send your commits up to GitHub (push); fetch others' commits down (pull).

## The everyday loop

You'll do this over and over:

```bash
git status                 # what have I changed? (run this any time you're unsure)
git add .                  # stage the changes you want to save
git commit -m "message"    # save them as one commit, with a message
git push                   # send your commits up to GitHub
```

And when you start work, or someone else has pushed:

```bash
git pull                   # bring down the latest commits from GitHub
```

Good commits are **small and focused** — one idea each, with a message that finishes the
sentence "This commit will…" ("add a contact form", "fix the broken image link"). Small commits
are easy to review and easy to undo.

## Branches and pull requests (the safe way to change things)

The habit worth building from day one: **don't change `main` directly.** Instead:

```bash
git checkout -b add-contact-form    # make + switch to a new branch
# ...do the work, commit as you go...
git push -u origin add-contact-form # push the branch to GitHub
```

Then on GitHub, open a **pull request (PR)** — a proposal to merge your branch into `main`.
It shows exactly what changed, runs any automated checks, and is where review happens. When it's
approved, you merge it, and `main` now includes your work. `gh pr create` opens one from the
terminal.

This is why the dev-hooks **dangerous-command guard** asks you to confirm if you try to commit
or push straight to `main` — it's nudging you toward a branch + PR instead. (That check is
switched on by the setup's starter settings; see
[`claude-config.md`](claude-config.md).)

## Undoing mistakes (nothing is as scary as it looks)

- **Unstage a file** you added by accident: `git restore --staged <file>`
- **Throw away uncommitted edits** to a file: `git restore <file>` *(this deletes those edits —
  the guard will ask you to confirm a blanket `git restore .`)*
- **Undo the last commit but keep the changes:** `git reset --soft HEAD~1`
- **See history:** `git log --oneline`
- **Go look at an old version** without changing anything: `git checkout <commit-hash>`, then
  `git checkout main` to come back.

Two commands genuinely destroy work with no undo — `git reset --hard` (wipes uncommitted
changes) and `git clean -f` (deletes untracked files). The guard asks you to confirm both.
**As long as you've committed and pushed, your work is safe** — that's the whole point of the
everyday loop.

## How Claude uses Git

When Claude is working it will typically: make a branch, edit files, commit with a clear
message, push, and open a PR. You'll see these commands go by. If you ever want to know the
current state, ask Claude to "show `git status`" or "show the recent commits" — or run
`git status` yourself. You're always allowed to slow it down and look.
