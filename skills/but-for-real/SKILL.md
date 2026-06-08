---
name: but-for-real
description: Use when about to claim something is done, fixed, working, passing, or ready to ship; when a change has only been eyeballed or pattern-matched rather than actually run; or when the user says "but for real", "for real this time", "don't guess", or "did you actually test it". Triggers on premature success claims, unverified fixes, and hand-waving instead of inspecting the real code.
---

# But For Real

Drop the optimistic frame. **"Should work" ≠ "does work."** Assume a bug exists and go find it before claiming otherwise. This operationalizes the "Always Works" rule in `~/.claude/CLAUDE.md`.

## The discipline

1. **Assume it's broken.** Start from "there is a bug" and try to prove it, not "this looks right."
2. **Re-read the real code.** Open the actual files you changed *now* — not your memory of them. Read the surrounding code paths, not just the lines you touched.
3. **List concrete failure modes.** Edge cases, empty/null inputs, error paths, the integration boundary, the thing you didn't change but depend on.
4. **Run it.** Trigger the exact feature you changed and watch the real result. Match the test to the change: UI → click it; API → call it; data → query it; logic → run the scenario; config → restart and load it.
5. **Separate observed from assumed.** Every claim is either "I ran X and saw Y" (observed) or "I expect Y" (assumed). Say which.

## Output

Report back as:
- **Verified** — what you ran and the result you saw with your own eyes
- **Still assumed** — claims you have *not* yet proven by execution
- **Bugs found** — anything the scrutiny surfaced
- **Verdict** — ship / don't ship, and what's left to verify

## Red flags — STOP, you're about to violate this

- "This should work now" / "I've fixed it" / "try it now" — before you ran it yourself
- "The logic looks correct" / "this matches the pattern"
- "It's a trivial change, no need to test"
- "I'll say it's done and the user can check"
- Reporting a test as passing without seeing the actual output

**All of these mean: go run it and look before you claim.**

## Rationalization table

| Excuse | Reality |
|--------|---------|
| "It's a one-line change" | One-line changes ship outages. Running it takes seconds. |
| "I already read it carefully" | Reading ≠ running. You can't read your way to runtime behavior. |
| "Tests probably pass" | "Probably" is a guess. Run them and read the output in full. |
| "The user can verify" | If you're claiming it works, you verify it. Otherwise say "unverified". |
| "No time to test" | Shipping a broken fix costs far more time than testing it. |
| "Empty read just means empty" | Reads can fail silently — never invent results to fill a gap. Verify the file/API actually returned what you think. |

See also [[verification-before-completion]] and [[systematic-debugging]]. To grade how confident you actually are, [[self-rate]].
