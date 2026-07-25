---
name: pr-screenshots
description: Use before opening or updating a PR whose diff touches frontend/UI files (views, components, CSS, JSX/TSX/Vue templates) — capture before/after screenshots of the changed screens and attach them to the PR so reviewers see the visual result without checking out the branch. Triggers on "add screenshots to this PR", "show the before/after", "attach a screenshot for review", or as a pre-PR step whenever the changed-file list is UI-shaped.
---

# PR Screenshots

A reviewer reading a UI diff has to mentally render markup/CSS into pixels, or check out the
branch to look. Close that gap yourself: capture the affected screen before and after your
change, annotate what moved, and put the images directly in the PR description.

## When this applies

Run `git diff --name-only --diff-filter=d <base>...HEAD` against the PR's base branch. If any
changed file is UI-shaped (view/template, component, stylesheet, JSX/TSX/Vue/Svelte, or a
Stimulus/React controller driving layout) and the project has a way to render it (a dev server,
a component-preview/Storybook build, or an existing e2e/browser-test setup), screenshots apply.
A pure backend/API diff with no rendered surface — skip this skill entirely.

## Procedure

1. **Launch the affected screen.** Use whatever this project already has for driving a real
   browser against it — an existing Playwright/Cypress/Capybara e2e setup, a component preview
   server (Storybook, Ladle), or the project's own dev server reachable over HTTP. Don't invent
   a new browser-automation stack for a repo that has none; if nothing renders the UI locally,
   say so and skip screenshots rather than screenshotting a static file.
2. **Capture "before".** Check out the PR's base commit (or `git stash` uncommitted work),
   start the app, navigate to each affected screen/state, and screenshot it. Restore your
   branch afterward (`git stash pop` / `git checkout -`) before continuing.
3. **Capture "after".** Same screens, same viewport size and data/state, on your actual
   change. Keep before/after viewport dimensions identical or the diff is misleading.
4. **Annotate only what changed.** Don't just paste two full-page screenshots — crop to the
   changed region and mark it up (a red box or arrow around the moved/added/restyled element).
   A reviewer should be able to tell what to look at in under two seconds.
5. **Attach to the PR, not just the chat.** Screenshots that only appear in your conversation
   never reach the reviewer. Put them in the PR description or a PR comment as embedded images —
   check what your git host's tooling supports (an MCP tool with native image upload, an image
   pasted through the host's web UI, or committing the files into the repo/branch and
   referencing them by path) rather than assuming one mechanism works everywhere.
6. **Caption each image** with the screen/state name and one line of what changed — "Settings
   page, dark mode: save button now full-width on mobile" — so the image is legible without
   opening it first.

## Multi-screen changes

If the diff touches several independent screens or states (e.g. a shared component used in
three places), screenshot each one separately rather than one composite image — reviewers scan
a stack of small, labeled images faster than one giant collage.

## Scope

This skill produces evidence for a PR description; it doesn't replace a code review. Pair it
with your normal review step (`/code-review`, a code-reviewer agent) — screenshots show *what*
changed visually, not whether the implementation is correct.
