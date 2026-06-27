#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
# short-description: One-line summary shown in the session-start script index.
"""Canonical template for a saved script in the library (~/.local/bin).

Copy this file, rename it, and replace the metadata and body — but keep the four marked
elements that make it a first-class library script:

  1. the `#!/usr/bin/env -S uv run --script` shebang, so it runs standalone once uv is
     installed (no virtualenv, no pip install);
  2. the PEP 723 `# /// script` block declaring `requires-python` + `dependencies`
     (list third-party libs there; uv resolves them at run time);
  3. the `# short-description:` line — the SessionStart script-index hook surfaces this so
     future sessions know what the tool is for at a glance;
  4. an argparse parser, so `<script> --help` explains usage in detail (the index points
     Claude here for more than the one-liner).

The example below just greets a name; swap in real logic.
"""

import argparse


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Replace me: one-line summary of what this script does.",
    )
    parser.add_argument("name", nargs="?", default="world", help="who to greet")
    parser.add_argument("--shout", action="store_true", help="upper-case the greeting")
    args = parser.parse_args()

    greeting = f"Hello, {args.name}!"
    print(greeting.upper() if args.shout else greeting)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
