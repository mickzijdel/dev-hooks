# Plain words — coding jargon, explained once

The setup talks to people who have **never coded before**. This is the shared vocabulary for
doing that well: every term gets one everyday comparison, no circular definitions, no jargon
inside the explanation. When you (Claude) use one of these words with a beginner for the first
time, introduce it with its analogy here — then you can use the word freely afterwards.

The same analogies appear in the bootstrap installer (`install.sh`) and the checklist page
(`onboard.html`). Keep all three in step so a beginner hears the same description everywhere.

## The basics

- **Terminal** — a window where you type instructions to your computer instead of clicking
  buttons. The instructions are called commands.
- **Command** — one instruction you paste or type into the terminal and run by pressing Enter.
- **Claude Code** — an AI helper that lives in the terminal and can set things up, write code,
  and run commands for you.
- **Signing in / logging in** — proving it's you, exactly like signing into any app or website.
- **Plugin** — an add-on that teaches Claude a new skill, like installing an app on a phone.
- **Marketplace** — the "app store" those add-ons come from.

## The toolbox

- **Package manager** — one tool that installs and updates your other tools for you, like an
  app store for programming tools. (mise is the one we use; see [`tools.md`](tools.md).)
- **Library / package** — a chunk of code someone else already wrote that your project borrows
  instead of writing it from scratch.
- **Environment variable** — a small named setting your computer remembers and hands to
  programs, like a sticky note that says `MY_KEY = abc`.
- **PATH** — the list of folders your terminal searches when you type a command, so it knows
  where to find each tool.

## Saving and sharing work

- **Git** — a tool that saves a snapshot of your whole project every time you ask, so you can
  go back to any earlier version. Like unlimited undo with labels.
- **Repository ("repo")** — one project's folder, with all of its saved history, tracked by Git.
- **Branch** — a parallel copy of your project where you can try a change safely without
  touching the working version. Merge it back when you're happy.
- **GitHub** — a website where coders store their repositories online, back them up, and share
  them. Think "the cloud, for code."
- **Pull request ("PR")** — a proposal to merge one branch into another, with a place to review
  the change before it lands.

## Running and shipping

- **Editor** — the app where you read and write code (we use VS Code).
- **Server** — a program that stays running and answers requests, like the thing behind a
  website that sends pages to visitors.
- **Docker / container** — a sealed box holding an app and everything it needs, so it runs the
  same on any computer instead of "works on mine."
- **Deploy** — putting your project online so other people can use it.

## At the command line

- **Diff** — the before/after view of what changed in a file: lines removed and lines added,
  side by side. (`delta` makes git's diff easy to read.)
- **Syntax highlighting** — coloring code so the different parts (keywords, text, numbers) stand
  out, the way an editor does. (`bat` adds it when printing a file.)
- **Fuzzy finder** — an interactive search that narrows a list as you type a few letters, and
  doesn't need the exact spelling — close is enough. (`fzf` is one.)
- **YAML / JSON** — two common text formats for settings and data. Lots of config files are
  written in them. (`jq` reads JSON; `yq` reads YAML.)
- **Benchmark** — a timed test that measures how long something takes, so you can compare two
  ways of doing it. (`hyperfine` benchmarks commands.)
- **Symlink** — a file that's really a pointer to another file, like a desktop shortcut. Opening
  it opens the real file. (We point `CLAUDE.md` at `AGENTS.md` this way.)

## How to use this list

- One new word at a time. Don't define five terms in one breath.
- Lead with the everyday comparison, then the real word — "a sealed box that runs the same
  anywhere (a **container**)", not "a container, i.e. an OS-level virtualization primitive."
- If a beginner already knows a term, skip the explanation — don't lecture.
