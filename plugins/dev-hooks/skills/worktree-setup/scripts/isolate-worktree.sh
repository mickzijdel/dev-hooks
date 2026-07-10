#!/usr/bin/env bash
# worktree-setup isolate: give a worktree its own server + database so parallel worktrees
# don't collide on the same port and the same DB.
#
# setup-worktree.sh copies .env / config/master.key into every worktree VERBATIM — so N
# worktrees all point at the same port and the same database. This script closes that gap: it
# allocates a stable, collision-free per-worktree offset from a registry shared by all
# worktrees, then writes the derived values into a gitignored `mise.local.toml` overlay (which
# layers over the committed mise.toml) — never mutating the copied .env. Host-native runs read
# PORT + the DB suffix; a per-worktree devcontainer reads COMPOSE_PROJECT_NAME.
#
# It is OPT-IN: with no `.worktree-isolate.conf` in the worktree it is a no-op. The config
# (committed — it describes the project, not secrets) declares what to isolate:
#   WT_BASE_PORT=3000                    # PORT = base + per-worktree offset
#   WT_EXTRA_PORTS="VITE_PORT=3036 …"    # space-separated NAME=base pairs, each += offset
#   WT_DB_SUFFIX_VAR=WORKTREE_DB_SUFFIX  # export "_<slug>" for database.yml to read
#   WT_REDIS_URL_VAR=REDIS_URL           # redis://localhost:6379/<offset>
#   WT_COMPOSE_NAME=myapp                # emit COMPOSE_PROJECT_NAME=<name>_<slug>
#   WT_COMPOSE_ENV=.devcontainer/.env    # also write name+PORT into this compose-adjacent .env
#
# Usage: isolate-worktree.sh [WORKTREE] [--config FILE]
#   WORKTREE     the worktree to isolate (default: $PWD)
#   --config FILE  the isolation config (default: WORKTREE/.worktree-isolate.conf)
#
# Emits KEY=VALUE lines on stdout (worktree, config, slug, offset, port, db_suffix,
# redis_index, compose_project, ports_written, mise_local), then "# " summary lines.

set -u

MARK_BEGIN='# >>> worktree-isolate (generated) — safe to delete >>>'
MARK_END='# <<< worktree-isolate (generated) <<<'

WT=""
CONF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --config)
      CONF="${2:-}"
      shift 2
      ;;
    --config=*)
      CONF="${1#--config=}"
      shift
      ;;
    -h | --help)
      sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      WT="$1"
      shift
      ;;
  esac
done

[ -n "$WT" ] || WT="$PWD"
if ! WT="$(cd "$WT" 2>/dev/null && pwd -P)"; then
  echo "isolate-worktree: worktree path does not exist" >&2
  exit 1
fi
[ -n "$CONF" ] || CONF="$WT/.worktree-isolate.conf"

emit_empty() {
  cat <<EOF
worktree=$WT
config=none
slug=
offset=
port=
db_suffix=
redis_index=
compose_project=
ports_written=0
mise_local=
EOF
  echo "# No .worktree-isolate.conf — worktree isolation skipped (nothing to do)."
  exit 0
}

[ -f "$CONF" ] || emit_empty

# ── read config (KEY=VALUE; strip inline # comments and surrounding whitespace) ───────────
conf_get() {
  sed -n "s/^[[:space:]]*$1=//p" "$CONF" | sed -e 's/#.*//' -e 's/[[:space:]]*$//' | tail -1
}
BASE_PORT="$(conf_get WT_BASE_PORT)"
EXTRA_PORTS="$(conf_get WT_EXTRA_PORTS | tr -d '"')"
DB_SUFFIX_VAR="$(conf_get WT_DB_SUFFIX_VAR)"
REDIS_URL_VAR="$(conf_get WT_REDIS_URL_VAR)"
COMPOSE_NAME="$(conf_get WT_COMPOSE_NAME)"
COMPOSE_ENV="$(conf_get WT_COMPOSE_ENV)"

# ── slug: sanitized branch name, else the worktree's basename ─────────────────────────────
slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | LC_ALL=C sed 's/[^a-z0-9]/_/g'; }
branch="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
if [ -z "$branch" ] || [ "$branch" = HEAD ]; then
  slug="$(slugify "$(basename "$WT")")"
else
  slug="$(slugify "$branch")"
fi

# ── allocate a stable, collision-free offset from the shared registry ──────────────────────
# The registry lives in the git *common* dir (shared by every worktree, never committed). We
# prune entries whose worktree no longer exists, reuse this slug's offset if it has one, else
# take the lowest free offset >= 1 (offset 0 is the un-provisioned main checkout on the base
# port).
common_dir="$(git -C "$WT" rev-parse --git-common-dir 2>/dev/null)"
case "$common_dir" in
  /*) : ;;
  *) common_dir="$WT/$common_dir" ;;
esac
REG="$common_dir/worktree-ports.tsv"
touch "$REG" 2>/dev/null || true

live_file="$REG.live.$$"
git -C "$WT" worktree list --porcelain 2>/dev/null | awk '
  function base(p, n, a) { n = split(p, a, "/"); return a[n] }
  /^worktree / { if (seen) emit(); path = substr($0, 10); br = ""; seen = 1 }
  /^branch /   { br = $2; sub(/^refs\/heads\//, "", br) }
  END { if (seen) emit() }
  function emit() { print (br != "" ? br : base(path)) }
' | while IFS= read -r name; do printf '%s\n' "$(slugify "$name")"; done >"$live_file"

reg_new="$REG.new.$$"
offset="$(awk -v cur="$slug" -v regout="$reg_new" '
  NR == FNR { live[$0] = 1; next }
  {
    if ($1 in live) { keep[$1] = $2; used[$2] = 1; if ($1 == cur) curoff = $2 }
  }
  END {
    if (curoff == "") { o = 1; while (o in used) o++; curoff = o; keep[cur] = o }
    for (s in keep) print s "\t" keep[s] > regout
    print curoff
  }
' "$live_file" "$REG")"
mv "$reg_new" "$REG" 2>/dev/null || true
rm -f "$live_file" 2>/dev/null || true

# ── build the env values from the offset ──────────────────────────────────────────────────
env_lines=""
compose_project=""
redis_index=""
ports_written=0
add_env() { env_lines="${env_lines}$1 = \"$2\""$'\n'; }

port=""
if [ -n "$BASE_PORT" ]; then
  port=$((BASE_PORT + offset))
  add_env PORT "$port"
  ports_written=$((ports_written + 1))
fi
for tok in $EXTRA_PORTS; do
  name="${tok%%=*}"
  eb="${tok#*=}"
  [ -n "$name" ] && [ "$name" != "$tok" ] || continue
  add_env "$name" "$((eb + offset))"
  ports_written=$((ports_written + 1))
done

db_suffix=""
if [ -n "$DB_SUFFIX_VAR" ]; then
  db_suffix="_$slug"
  add_env "$DB_SUFFIX_VAR" "$db_suffix"
fi
if [ -n "$REDIS_URL_VAR" ]; then
  redis_index="$offset"
  add_env "$REDIS_URL_VAR" "redis://localhost:6379/$offset"
fi
if [ -n "$COMPOSE_NAME" ]; then
  compose_project="${COMPOSE_NAME}_$slug"
  add_env COMPOSE_PROJECT_NAME "$compose_project"
fi

# ── write the generated block idempotently (strip any prior block, then append) ───────────
strip_block() {
  awk -v s="$MARK_BEGIN" -v e="$MARK_END" '
    $0 == s { inblk = 1 }
    !inblk  { print }
    $0 == e { inblk = 0 }
  ' "$1"
}
write_block() { # <file> <body>
  local f="$1" body="$2" kept=""
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] && kept="$(strip_block "$f" | sed -e :a -e '/^\n*$/{$d;N;ba}')"
  {
    [ -n "$kept" ] && printf '%s\n\n' "$kept"
    printf '%s\n' "$MARK_BEGIN"
    printf '%s' "$body"
    printf '%s\n' "$MARK_END"
  } >"$f"
}

MISE_LOCAL="$WT/mise.local.toml"
write_block "$MISE_LOCAL" "[env]"$'\n'"$env_lines"

if [ -n "$COMPOSE_ENV" ]; then
  compose_body=""
  [ -n "$compose_project" ] && compose_body="${compose_body}COMPOSE_PROJECT_NAME=$compose_project"$'\n'
  [ -n "$port" ] && compose_body="${compose_body}PORT=$port"$'\n'
  write_block "$WT/$COMPOSE_ENV" "$compose_body"
fi

# ── output ────────────────────────────────────────────────────────────────────────────────
cat <<EOF
worktree=$WT
config=$CONF
slug=$slug
offset=$offset
port=$port
db_suffix=$db_suffix
redis_index=$redis_index
compose_project=$compose_project
ports_written=$ports_written
mise_local=$MISE_LOCAL
EOF

echo "# Isolated worktree $WT as offset $offset (slug $slug)."
[ -n "$port" ] && echo "# PORT=$port; wrote $ports_written port var(s) to mise.local.toml."
[ -n "$db_suffix" ] && echo "# Database suffix $db_suffix (via $DB_SUFFIX_VAR)."
[ -n "$compose_project" ] && echo "# COMPOSE_PROJECT_NAME=$compose_project."

exit 0
