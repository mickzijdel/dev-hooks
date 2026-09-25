# Where the budgets come from

`slop_scan.py`'s metric budgets are not taste. They come from measuring codebases written
before LLM assistance existed and asking what those codebases actually do.

## Method

Four reference codebases, all tagged before 2023 and all still maintained today:

| Codebase | Tag | Released | Language |
|---|---|---|---|
| Django | 4.0 | Dec 2021 | Python |
| Flask | 2.0.0 | May 2021 | Python |
| requests | 2.27.0 | Jan 2022 | Python |
| git | v2.34.0 | Nov 2021 | shell |

Counted `#` line comments only — not docstrings, so the Python figures understate total
documentation. Lint and tooling directives (`noqa`, `shellcheck`, `type: ignore`, SPDX,
encoding lines) were excluded from every corpus. Test directories were excluded from the
reference corpora.

## Comment density

Comment lines per 100 code lines:

| Corpus | Density | Median words/comment | Comments in multi-line blocks |
|---|---|---|---|
| Django 4.0 | 9.9% | 8 | 67% |
| Flask 2.0 | 10.7% | 8 | 90% |
| requests 2.27 | 12.1% | 7 | 60% |
| git 2.34 (shell) | 10.1% | 7 | 69% |
| **dev-hooks hooks (shell, AI-written)** | **49.8%** | **12** | **83%** |

Four independent codebases, two languages, different decades of origin, all converging on
roughly 10%. The AI-written corpus sits five times higher.

The `--max-density` default is 15%, comfortably above the top of the human range, so that
ordinary human-written code does not trip it.

## Comment register

Of the comments in each corpus, the share containing each marker:

| Marker | Django | git (shell) | dev-hooks (shell) |
|---|---|---|---|
| Em dash | 0.6% | 0.4% | 18.7% |
| Parenthetical | 11.0% | 13.5% | 39.0% |
| Semicolon | 1.2% | 1.5% | 8.1% |

A thirty-fold difference in em-dash rate is the single sharpest signal measured.

There is a matching structural difference. Only 28.6% of the AI corpus's comments sit
directly above a line of code, against 52.9% in Django: AI comments float as standalone
explanatory paragraphs, where human comments annotate a specific line.

Side by side:

```python
# cx_Oracle does not always convert None to the appropriate        ← Django
# rel_opts.object_name == "Target"
# token.split_contents() isn't useful here because this tag doesn't accept
# Don't alter when:
```

```bash
# Every gate errs toward silence: a missed thin brief costs         ← AI-written
#   nothing, a false nudge costs attention.
# Runtime state the app actually reads: uploads/blobs, secrets, env,
#   service-account keys. These …
```

Human comments are clipped fragments that name identifiers — frequently no verb, no
capital, no full stop, often a continuation of the line above. AI comments are complete
sentences about policy, balanced and self-explaining.

## Why this matters for the survival rule

The [[compress-comments]] skill asks one question of each comment: does it state something
the code cannot show? Every comment in that AI sample passes — they are real constraints
and real gotchas. The rule is sound and still lands at five times human density, because
it is a **per-comment** test with no budget and no register test. Over budget, the question
stops being "does this one survive?" and becomes "which of these is most worth keeping?"

## Scanner precision against these corpora

Findings per file after tuning:

| Corpus | Files | Findings | Per file |
|---|---|---|---|
| Django + Flask + requests | 1402 | 231 | 0.16 |
| git 2.34 shell | 1133 | 268 | 0.24 |
| dev-hooks hooks (AI-written) | 32 | 76 | 2.38 |

Roughly a tenfold separation. Rules that could not reach that separation were cut rather
than kept at a lower confidence — see the comments in `scripts/slop_scan.py` for which
ones and why.

## What was measured and rejected: complexity concentration

SlopCodeBench separates two failure modes — code grows verbose without concentrating
complexity, and complexity concentrates without the code growing. The comment metrics
measure the first. A branch-counting pass for the second was built, measured against
these same corpora, and **cut**. The numbers, so nobody re-litigates it:

**Branch density per file** (control-flow keywords per 100 code lines) does not separate
authorship at all:

| Corpus | Median | p90 |
|---|---|---|
| Django 4.0 | 14.4 | 22.0 |
| requests 2.27 | 14.7 | 19.4 |
| dev-hooks hooks (AI-written) | 18.2 | 24.1 |

**Concentration as a share** (% of a file's branches in its largest function) is worse:
Django's own p90 is 73% and its p99 is 100%. Human code concentrates routinely.

**Worst-function branch count** is the only version with a real signal, and its cost is
still too high. Findings per file, swept over thresholds:

| Corpus | Files | >10 | >12 | >15 | >20 |
|---|---|---|---|---|---|
| Human Python (Django + Flask + requests) | 900 | 0.26 | 0.16 | 0.11 | 0.05 |
| Human shell (git 2.34) | 1133 | 0.01 | 0.00 | 0.00 | 0.00 |
| AI Python (dev-hooks + writing skills) | 12 | 0.67 | 0.33 | 0.25 | 0.17 |

At the best threshold the separation is about 2×, against 5× for comment density and 30×
for em-dash rate — and adding it at `>12` would have doubled the scanner's entire
false-positive budget on human Python, from 0.16 findings per file to 0.32. The AI
sample is also only 12 files, too small to conclude from.

The deeper reason it does not belong here: **function complexity is a code-quality
signal, not an authorship signal.** A 15-branch function deserves a look whoever wrote
it, and that job is already done better by real AST tools than by a regex approximation
of one. So the skill runs those instead — see *Complexity* in [SKILL.md](../SKILL.md).

## Reproducing

```bash
git clone --depth 1 --branch 4.0 https://github.com/django/django
slop_scan.py --metrics-only $(find django/django -name '*.py')
```

Re-run this before changing a budget. A budget moved without a measurement behind it is
the thing this file exists to prevent.
