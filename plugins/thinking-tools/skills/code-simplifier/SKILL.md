---
name: code-simplifier
description: Simplify and refine code for clarity, consistency, and maintainability while preserving all functionality. Use after modifying code, when asked to simplify or clean up code, or during refactoring. Focuses on recently changed sections unless directed otherwise.
---

# Code Simplifier

Refine code for improved clarity, consistency, and maintainability — change only *how* code works, never *what* it does.

## Principles

1. **Preserve functionality** — Modifications change implementation only; behavior stays identical.
2. **Apply project standards** — Respect established conventions from CLAUDE.md and project docs.
3. **Enhance clarity** — Better naming, structure, and organization. Prefer readable, explicit code over compact one-liners or nested ternaries.
4. **Maintain balance** — Avoid over-simplification that obscures intent or removes useful abstractions.
5. **Focus scope** — Concentrate on recently modified sections unless directed otherwise.

## Workflow

1. Identify modified or targeted code sections.
2. Analyze each for improvement opportunities (naming, duplication, structure, clarity).
3. Apply changes that improve clarity without altering behavior.
4. Verify functionality is unchanged.
5. Note any significant structural changes.

---

**Credit:** Adapted from [Nate Berkopec's dotfiles](https://github.com/nateberkopec/dotfiles/blob/main/files/home/.claude/skills/code-simplifier/SKILL.md), which is itself adapted from Anthropic's official `code-simplifier` plugin.
