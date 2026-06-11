#!/bin/bash
# PostToolUse(Write): when Claude creates a NEW project-manifest or framework-entrypoint
# file by hand (Gemfile, package.json, config/application.rb, …), nudge it to run the
# framework's official generator (`rails new`, `npm create vite@latest`, `cargo new`, …)
# instead of scaffolding the skeleton from memory. Generators produce a current, complete
# skeleton; hand-written scaffolds drift from current versions and miss wiring.
#
# Write-tool only (an Edit to a manifest means the project already exists), and only for
# files git doesn't already track (a tracked manifest is an existing project, not fresh
# scaffolding; outside a git repo every file counts as new). Advisory only — emits
# additionalContext and always exits 0, never blocks. Fires at most once per session.
#
# Opt out per repo/user with DEV_HOOKS_SCAFFOLD=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
# Sets INPUT, FILE, SESSION, TOOL, BASE (or exits 0 on opt-out / missing file_path).
reminder_init DEV_HOOKS_SCAFFOLD

[ "$TOOL" = "Write" ] || exit 0

# Map manifest/entrypoint to the generator(s) to suggest. Entrypoint files that only
# signal a framework at a specific path (config/application.rb) match on the FILE tail.
SUGGESTION=""
case "$BASE" in
  Gemfile) SUGGESTION="\`rails new\` for a Rails app, \`bundle gem\` for a gem" ;;
  package.json) SUGGESTION="\`npm create vite@latest\`, \`npx create-next-app@latest\`, or the framework's own CLI (\`npm init\` for a bare package)" ;;
  pyproject.toml) SUGGESTION="\`uv init\`, \`django-admin startproject\`, or the framework's own CLI" ;;
  manage.py) SUGGESTION="\`django-admin startproject\`" ;;
  Cargo.toml) SUGGESTION="\`cargo new\` / \`cargo init\`" ;;
  go.mod) SUGGESTION="\`go mod init\`" ;;
  mix.exs) SUGGESTION="\`mix new\`, or \`mix phx.new\` for Phoenix" ;;
  composer.json | artisan) SUGGESTION="\`composer create-project\` (\`laravel new\` for Laravel)" ;;
  build.gradle | build.gradle.kts | pom.xml) SUGGESTION="\`gradle init\` or Spring Initializr (\`spring init\`)" ;;
  application.rb)
    case "$FILE" in
      */config/application.rb) SUGGESTION="\`rails new\`" ;;
    esac
    ;;
esac
[ -z "$SUGGESTION" ] && exit 0

# Already tracked by git → an existing project's file, not fresh scaffolding.
DIR=${FILE%/*}
[ "$DIR" = "$FILE" ] && DIR=.
git -C "$DIR" ls-files --error-unmatch -- "$FILE" >/dev/null 2>&1 && exit 0

# Fire at most once per session.
reminder_fire_once scaffold || exit 0

MSG="You're creating $BASE by hand — this looks like new-project scaffolding. Use the framework's official generator instead of writing the skeleton from memory (here: $SUGGESTION). A generator produces a current, complete skeleton with the right versions, config, and wiring. First check the framework's current stable release (e.g. \`gem list rails --remote\`, \`npm view <pkg> version\`, the project's releases page) and use that unless the user asked for a specific version, and check the generator's current flags via \`--help\` or its docs rather than recalling them. If this is an existing project or a deliberately minimal manifest, ignore this."

reminder_emit "$MSG"
