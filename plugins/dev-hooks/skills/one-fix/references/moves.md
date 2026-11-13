# Moves that replace many guards with one rule

Pick the first that fits the group. Each names where the rule lives afterwards.

| Move | When the guards look like | The one change |
|---|---|---|
| **Normalise at the boundary** | the same trim, lowercase, default, timezone or unit conversion at several call sites | convert once where the value enters (request parser, form object, importer) into a type the rest of the code trusts; delete the conversions inside |
| **Make the state unrepresentable** | checks for combinations that should never occur (`paid` without `paid_at`, two flags both true, nullable where a value is always needed) | one enum or tagged union in place of the flags; `NOT NULL`, a check constraint or a unique index in the schema |
| **One source of truth** | code that re-syncs, re-counts or reconciles a copy; bugs where two values disagree; two parsers or implementations of the same rule that drift apart | store one, derive the other (a method, a view, a generated column); keep one implementation and have the other callers read its result; delete the sync code and the second copy |
| **Require it** | fallbacks for a missing tool, interpreter, config value or optional field, each degrading differently | declare the dependency required and check it once at startup or load; delete the fallbacks |
| **Move the check to the chokepoint** | the same permission, validation or existence check in many callers, and a bug wherever one caller forgot it | put it in the one function every caller goes through; if none exists, create it and route the callers there |
| **Make the operation total** | callers wrapping a call in `if exists`, `rescue NotFound`, `if list.any?` | change the operation so the edge case is a normal result: idempotent delete, empty list instead of nil, upsert instead of find-then-create |
| **Replace the cases with the rule** | a growing `if`/`case` ladder or lookup table, extended once per bug report | implement the rule the cases are samples of (the real parser, the library function, the general algorithm) |
| **Carry it in the type** | recurring mix-ups of units, currencies, ids of different tables, escaped and raw strings | a small wrapper type per kind, so the wrong mix does not compile or raises at construction |

## Signs the group has no single fix

- The rows defend against inputs from different origins that share no entry point.
- The bad value is allowed by an external contract you do not control.
- The rows change for different reasons: unifying them couples two things that will
  diverge, and the wrong abstraction costs more than the duplication.
