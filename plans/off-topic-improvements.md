# Off-topic improvements (noticed, out of scope)

- `tests/conftest.py` — `init_git_repo`'s docstring says it initialises the repo
  "with one commit", but the function never commits (init + config + optional
  remote only). Fix the docstring, or add the commit if tests would benefit from
  a non-empty `HEAD` baseline.
