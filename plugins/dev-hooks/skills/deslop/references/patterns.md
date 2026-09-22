# Slop catalogue — detect → act

Three tiers by what you are allowed to do about them. Tier A you delete on sight, Tier B
you fix and report because it is a latent bug, Tier C you only ever propose.

The tiering and much of Tier A/B is adapted from Andrii Paslavskyi's `anti-slop` plugin
(MIT) — see the credit in [SKILL.md](../SKILL.md). Tier A's comment rows and the density
row are this skill's own, from [measurements.md](measurements.md).

## Tier A — delete silently

No report, no permission, no discussion. Deleting these is the job.

| # | Pattern | Detect | Action |
|---|---|---|---|
| A1 | Narration comment | Restates the line it sits on; `// increment counter`; section banners over a screen-sized block | Delete |
| A2 | Comment over budget | File is past ~15% comment density with no reason (reference table, vendored algorithm, format spec) | Rank the comments; keep the few carrying a constraint, delete the rest. See A3 before rewriting |
| A3 | Essay register | Complete sentences with em dashes, parentheticals, balanced clauses; comment floats rather than annotating a line | Rewrite as a fragment that names the identifier. Human codebases: 7–8 words, under 1% em dashes |
| A4 | Signature-restating docstring | `@param x the x`, a prose re-list of every parameter and type | Compress to a one-line summary plus real semantics (units, side effects, raises). Never delete a public-API docstring |
| A5 | Change narration | "Added for…", "Updated to…", "Previously this…" | Delete — git records it |
| A6 | Reviewer justification | "This is safe because…", "This cannot fail since…" | Delete. If safety rests on a *non-local* invariant, compress to a plain statement of that invariant |
| A7 | Redundant defensive check | Null/empty/type checks, `try`/`catch`, validation on a path whose caller already validated or that is internal | Trace the caller. Trusted → delete |
| A8 | Fallback-on-fallback | `else { /* fallback */ }`, branches "for unknown state", retry paths partially duplicating each other, a branch that does nothing | Collapse to one path. Unknown state throws, it does not silently return false |
| A9 | Type escape | `any`, `as any`, `as unknown as`, `@ts-ignore`, `# type: ignore`, `interface{}` | Type it properly, or use the type that already exists |
| A10 | Dead code | Unused imports, vars, params, functions; unreachable branches; commented-out code; flags nothing reads | Grep, then delete |
| A11 | Needless abstraction | One-use helper, class with a single static method, wrapper that only forwards, `*Utils`/`*Manager` with no state | Inline and delete |
| A12 | Duplicated state check | The same predicate literal in two or more places (`status === "paid"`) | Use the existing enum or helper. If none exists, that is C2 |
| A13 | Style drift | Naming, error handling, logging or import style unlike the rest of the file; emoji; prose in code | Match the file |
| A14 | Session residue | Debug prints, `console.log("HERE")`, `binding.pry`, empty or content-free TODOs, "temporary" markers | Resolve or delete. Flag any dropped TODO so intent is not lost silently |

## Tier B — fix, and report each

These pass tests today. They are bugs with a delayed fuse.

| # | Pattern | Detect | Action |
|---|---|---|---|
| B1 | Works-today encoding | Enum serialised by ordinal, magic numbers, assumptions about current cardinality, positional tuples crossing a boundary | Encode by name; make the assumption a type |
| B2 | Inconsistent result shape | One function returns `null`, `false`, `undefined`, `{ok}` for different failures | One result type, used consistently |
| B3 | Swallowed error | `catch { log; return undefined }`, bare `except:`, empty `if err != nil` | Rethrow or propagate a typed error |
| B4 | Honor-system gate | Security or behaviour gated on a name, a comment, or an env var with nothing enforcing it | Enforce at the boundary or remove the gate. Always flag to the user |
| B5 | Symptom patch | The fix adds a flag or special case at the symptom site rather than the cause | Root-cause it before patching |

## Tier C — propose only, never do

Structural erosion. Restructuring during a cleanup pass is how a cleanup becomes a rewrite.

| # | Pattern | Detect | Proposal shape |
|---|---|---|---|
| C1 | God file | File past ~600 lines, or the diff grew it by more than 20%; a new responsibility added to a class "because it fit" | Name the responsibilities; propose the split with file names |
| C5 | Complex function | Cyclomatic complexity over ~10, from the project's own linter (see *Complexity* in [SKILL.md](../SKILL.md)) — not from `slop_scan.py`, which does not measure it | Propose the decomposition, or say why it is irreducible |
| C2 | Missing system metaphor | One domain concept (an order, a session, a vault) handled by scattered inline checks; no type models it | Propose the model and name which checks it absorbs |
| C3 | Second way | A new util or pattern duplicating one the codebase already has | Propose deleting the new one and using the existing one |
| C4 | Special-case undercut | `if (user === X)` / `if (env === …)` changing how the core flow works | Propose moving it to config or strategy at the boundary |

## What the scanner can and cannot see

`slop_scan.py` finds A2, A3, A5, A9, A14, B3 and C1 mechanically, plus placeholder stubs
and leftover chat artifacts. It deliberately does **not** try to detect A1 narration: the
obvious rule ("comment opens with a verb naming what the next line does") fires on 222
Django comments that are real why-comments beginning "Set the …". Narration is judged by
whether a comment adds anything its line does not, which needs a reader.

It also does not measure function complexity (C5). A regex approximation of a cyclomatic
count was built and measured, and separated human from AI code only about 2× while
doubling the scanner's false-positive budget; the project's own AST linter does the job
properly. See *Complexity* in [SKILL.md](../SKILL.md) and the numbers in
[measurements.md](measurements.md).

Everything else in this table — A7, A8, A11, A12, all of Tier B beyond B3, all of Tier C
beyond C1 — needs someone who understands what the code is *for*. The scanner narrows
where to look. It does not do the looking.
