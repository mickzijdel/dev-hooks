# Off-topic improvements (noticed, out of scope)

## hooks/scripts/lint-on-edit.sh — `run_js` is defined but never called

`run_js()` (the bun/pnpm/npx fallback runner for JS/TS tools) is defined but never
invoked — the JS/TS arm calls `"$BIN/biome"` / `"$BIN/prettier"` / `"$BIN/eslint"`
directly instead. shellcheck flags this as SC2329 (silenced inline for now).

This looks like a latent bug: the direct `.bin` calls skip the broken-stub fallback that
`run_js` was written to provide. Likely fix: route those tool invocations through
`run_js` (e.g. `run_js biome check --write "$FILE"`), then drop the inline
`# shellcheck disable=SC2329`. Left as-is pending a decision on intended behaviour.
