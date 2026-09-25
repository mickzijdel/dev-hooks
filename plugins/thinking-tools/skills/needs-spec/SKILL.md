---
name: needs-spec
description: Use when asked to work through, clear, or process a repo's `need-spec`-labeled issue queue, or to spec out backlog issues with incomplete requirements. Triggers on "work the need-spec queue", "clear the spec backlog", "spec out open issues", "go through issues that need requirements", or as a scheduled agent. Interviews the user via grill one issue at a time until each has an agreed spec, then writes it back to the issue and drops the label.
---

# Needs Spec

Work a GitHub issue queue whose items are missing requirements: fetch every open issue labeled
`need-spec`, process oldest first, and for each one turn a vague ask into an agreed spec logged
on the issue itself.

## Procedure

1. **Fetch the queue.**
   ```bash
   gh issue list --label need-spec --state open --json number,title,createdAt \
     --jq 'sort_by(.createdAt) | .[] | "\(.number)\t\(.title)"'
   ```
   Empty queue → report that and stop.

2. **Per issue, oldest first:**
   - Read the full issue: `gh issue view <n> --comments`.
   - Summarize in one paragraph what the issue appears to be asking for and where it's
     underspecified — this is the seed for [[grill]], not a spec to rubber-stamp.
   - Run [[grill]] against that seed: interview the user one question at a time (scope,
     behavior, edge cases, acceptance criteria) until every branch is resolved.
   - Once the user confirms the resulting decision summary, append it to the issue body under
     a `## Resolved spec (YYYY-MM-DD)` heading — preserve the original body above it, never
     overwrite it — via `gh issue edit <n> --body-file`.
   - Remove the label: `gh issue edit <n> --remove-label need-spec`.
   - Move to the next issue.

3. **The user cuts an issue's interview short** — leave the label on, note which issue and why
   in the final summary, and move to the next one rather than guessing the rest of the spec.

## Done when

Every issue that was in the queue at step 1 is accounted for: either its label is removed and
the resolved spec is on the issue, or it's named in the summary as still open with a reason.
Report the count resolved vs. still open at the end.

## Composing with other skills

- The interview itself is [[grill]] — this skill only supplies the queue, the ordering, and
  where the outcome gets written.
- A resolved branch that was hard to reverse and cost real deliberation → [[adr]].
