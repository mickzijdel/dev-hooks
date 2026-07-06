# Comment smells

The taxonomy behind the survival rule (*a comment survives only if it states something the
code cannot show*). Each smell reads *what it is* → *disposition*, with a before/after.

## Delete

- **Code echo** — restates the line it sits on. → delete.
  ```python
  # increment the counter          ← delete
  count += 1
  ```
- **Change narration** — narrates the session, not the code: what was just changed or added.
  → delete; git history already records it.
  ```python
  # Now also handles unicode (updated after adding NFKD above)   ← delete
  slug = title.lower()
  ```
- **Planning forensics** — records the deliberation: which approaches were considered,
  which was picked. Sibling of change narration (narration = *what changed*, forensics =
  *what was decided*). → delete — **unless** it states the constraint that makes the obvious
  alternative wrong (a future reader would "fix" it back and break something); then compress
  to that constraint. A record of which options were weighed is never that constraint.
  ```python
  # We considered a regex here but went with str methods instead   ← delete
  # NFKD, not NFC: ligatures must decompose before the ASCII strip ← survives
  ```
- **Reviewer justification** — argues correctness to an imagined reviewer ("this is safe
  because…", "this cannot fail since…"). → delete; if the safety rests on a *non-local*
  invariant, compress to a plain statement of that invariant instead.
  ```python
  # This is safe because both args were already validated upstream ← delete
  # Args are validated as list[str] in the API layer               ← survives
  ```
- **Section header over a trivial block** — `# ── Setup ──`, `// Main logic`, in a function
  that fits on a screen. → delete.
- **Redundant with nearby doc** — repeats the docstring or an adjacent comment. → delete
  the copy.
- **Leftovers** — commented-out code, empty or content-free TODOs (`# TODO: implement`).
  → delete; flag dropped TODOs in the summary so intent isn't silently lost.

## Compress

- **Buried why** — a real constraint wrapped in narration. → keep the constraint, usually
  one line.
  ```python
  # We decided to use NFKD normalization here instead of NFC because we
  # want compatibility decomposition so that ligatures and accented
  # characters split apart before we strip to ASCII below.
  ```
  becomes
  ```python
  # NFKD: ligatures/accents must decompose before the ASCII strip below.
  ```
- **Signature-restating docstring** — prose re-listing every parameter, type, and the
  return value. → one-line summary plus only real semantics (units, side effects,
  invariants, raised errors). Never delete a public-API docstring outright.
  ```python
  """Slugify a title.

  Takes the title parameter, which is the title string to convert, and the
  max_len parameter, an integer defaulting to 80, and returns the slug string.
  """
  ```
  becomes
  ```python
  """Convert title into a URL-safe ASCII slug of at most max_len characters."""
  ```

## Survives untouched

Positive anchors — comments the skill must leave alone:

```python
# max_len-1 would cut mid-word; +1/rsplit trims to the last full word (issue #142)
# Retry once: the vendor API returns spurious 503s on cold start (their ticket #9241)
x = x.encode("ascii", "ignore").decode()  # noqa: PLW2901  ← directive: never touch
```
