---
name: env-to-fnox
version: 1.3.0
description: Use when a repo keeps secrets in plaintext .env or .env.local and the user wants them out, when setting up secrets for a new project, or on a mention of fnox, bws, Bitwarden Secrets Manager or "stop committing my .env".
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - AskUserQuestion
---

# env-to-fnox: Migrate `.env` to fnox

[fnox](https://fnox.jdx.dev) keeps secrets out of your repo by storing only **references**
in a `fnox.toml` and resolving the real values from a vault at run time. `fnox.toml` never
contains a secret value, so (in solo repos) it is safe to commit. This skill walks a `.env`
file through to fnox, defaulting to **Bitwarden Secrets Manager** (the `bitwarden-sm`
provider + `bws` CLI).

> **Two Bitwarden products — don't confuse them.** *Secrets Manager* (`bws` CLI, fnox
> `type = "bitwarden-sm"`) is purpose-built for app/dev secrets: a machine-account **access
> token** scoped to one project, read **and** write, no master-password unlock, works
> headless/CI. The older *Password Manager* (`bw` CLI, fnox `type = "bitwarden"`) is your
> personal vault — read-only from fnox and references items by name. This skill uses Secrets
> Manager; see the note in step 4 for the Password Manager variant.

fnox is provider-agnostic — Secrets Manager, 1Password, age, the OS keychain, AWS Secrets
Manager, Azure Key Vault, and HashiCorp Vault are all supported. Swap the provider block in
step 4 for a different backend.

**The token never sits in a shell.** `BWS_ACCESS_TOKEN` lives in the OS keychain behind the
global fnox config with `env = false`: no shell profile exports it and no shell hook loads
secrets, so an npm or gem install script can't harvest it. Everything that needs secrets runs
as `fnox exec -- <cmd>`. Don't suggest exporting the token or `fnox activate`.

## When to use

- A repo has real secrets sitting in `.env` / `.env.local`.
- The user wants secrets out of plaintext / out of version control.
- Setting up secrets management for a new project.

## Workflow

Work through these in order. Verify a real secret resolves before deleting anything.

> **Automation shortcut:** `scripts/migrate_env_to_fnox.py` automates steps 3, 4 and 7. It
> writes the `fnox.toml`, stores each secret with `fnox set` (value on stdin), and with
> `--verify` compares what fnox resolves against the `.env`, printing only `same`,
> `different` or `unresolved` per variable:
> ```bash
> scripts/migrate_env_to_fnox.py --env-file .env --project-id <PROJECT_ID> \
>   --key-prefix my-repo- --config PORT BASE_URL \
>   --shared KAMAL_REGISTRY_PASSWORD=kamal-registry-password --verify
> ```
> It reads the token itself (`fnox get -c ~/.config/fnox/config.toml BWS_ACCESS_TOKEN`) and
> hands it only to each `fnox set` child, because `fnox set`, unlike `fnox exec`, fails with
> "Access token not found" when the token is `env = false`. `--key-prefix` names every new
> key (`my-repo-database-url`); `--config` writes plain config as `{ default = "..." }`;
> `--shared VAR=key` references a key another repo already stores; every other variable is a
> new secret. `--dry-run` previews the plan without calling fnox or writing anything;
> `--delete-source` removes the `.env` afterward behind a typed `DELETE`. Still do step 1
> (which variables are config, which are shared) and step 2 first, and steps 5–6 after.

### 1. Analyze the existing `.env`

Read the `.env` (and `.env.local`, `.env.*`) and **categorise** each entry:

- **Real secrets** — API tokens, DB passwords, private keys, OAuth client secrets, signing
  keys. These move into the vault.
- **Shared secrets** — a value another repo already stores (a registry token used by every
  Kamal deploy). Reference the existing key rather than storing a copy.
- **Non-secret config** — ports, hostnames, feature flags, public keys, `NODE_ENV`. These do
  *not* belong in a vault; keep them as plain defaults in `fnox.toml` or `mise.toml`.

List what you found and which bucket each falls into before touching the vault.

### 2. Install the tools and store the token

```bash
mise use -g fnox bitwarden-secrets-manager   # installs fnox + the bws CLI
fnox --version && bws --version              # verify
```

Secrets Manager auth is a **machine-account access token**, not a login. One-time, in the
[Secrets Manager web console](https://bitwarden.com/help/secrets-manager-quick-start/):
create a **project**, create a **machine account**, grant it access to the project, and
generate an **access token** (shown once). Store it in the keychain via the global config
(the keychain provider must be registered first, or `set` errors with "Provider 'keychain'
not found"):

```bash
fnox init -g --skip-wizard                   # once, if no global config exists
fnox provider add keychain keychain -g       # register the provider globally
fnox set -g BWS_ACCESS_TOKEN --provider keychain   # prompts for the token, hidden
```

Then add `env = false` to the `BWS_ACCESS_TOKEN = { provider = "keychain", … }` entry that
wrote in `~/.config/fnox/config.toml`, so fnox uses the token to reach Bitwarden but never
passes it to a child process.

If the machine already has this, skip to step 3. The token only decrypts/edits the secrets in
its project — it can't touch a personal password vault.

### 3. Store the secrets in the vault (this provider is read **and** write)

Keys live in one shared project, so name them with a **repo prefix** in kebab case
(`my-repo-database-url`); `fnox.toml` maps the CAPS variable to that key.

`fnox set` writes the secret and its reference into `fnox.toml` (register the provider
first, step 4's two commands), but it does not fetch the
keychain token itself. Give the token to that one command only, and let fnox prompt for the
value so it never lands on a command line:

```bash
BWS_ACCESS_TOKEN="$(fnox get -c ~/.config/fnox/config.toml BWS_ACCESS_TOKEN)" \
  fnox set DATABASE_URL --provider bws --key-name my-repo-database-url   # hidden prompt
```

An agent has no terminal for that prompt: use the script, which pipes each value in on stdin.
`bws` itself (`bws secret create`, `bws secret edit`) needs the token in its env the same
way. **`bws secret list` is blocked for agents** by the dev-hooks secret guard, even piped to
`jq '.[].key'`, so you can't check for a key-name clash beforehand: write, then check with
step 7's same/different comparison. A `different` there usually means the key name was
already taken.

### 4. Configure `fnox.toml` (references only)

```bash
fnox init                                          # creates fnox.toml
fnox provider add bws bitwarden-sm                 # registers the provider
```

```toml
[providers]
bws = { type = "bitwarden-sm", project_id = "<PROJECT_ID>" }   # or set BWS_PROJECT_ID

[secrets]
# value = the secret's KEY NAME in Secrets Manager (NOT the secret itself)
DATABASE_URL = { provider = "bws", value = "my-repo-database-url" }
KAMAL_REGISTRY_PASSWORD = { provider = "bws", value = "kamal-registry-password" }  # shared

# Non-secret config stays as plain defaults (no provider):
PORT = { default = "3000" }
```

Append `/note` or `/key` to a value for those fields (e.g. `value = "database-url/note"`).

> **Password Manager variant:** for the personal-vault provider instead, use
> `bw = { type = "bitwarden" }`, reference items by name (`value = "ItemName"` →
> the item's password field, or `"ItemName/fieldName"`), and populate the vault yourself —
> that provider is **read-only**, so `fnox set --provider bw` would only inline the value
> (don't). Auth there is `export BW_SESSION=$(bw unlock --raw)`.

### 5. Wire it into the run-time

Wrap every command that needs secrets in `fnox exec -- <cmd>`: `fnox exec -- npm run dev`,
`fnox exec -- bin/rails server`, or in a mise task:

```toml
[tasks.dev]
run = "fnox exec -- bin/dev"
```

Don't use `fnox activate`: with the token `env = false` its prompt hook can't resolve a
Bitwarden secret and warns at every prompt.

> **Do NOT load fnox via `mise.toml [env] _.source` (or any mise env directive).** When fnox
> is a mise-managed tool it lives on `PATH` as a **mise shim**; calling it from inside mise's
> own env evaluation re-enters mise, which re-runs the directive → an infinite
> `bash → fnox → mise` fork loop that exhausts the kernel task limit.

Then fix whatever still expects the `.env` file:

- **Docker Compose `env_file: .env`** fails once the file is gone. Switch to an
  `environment:` passthrough (`environment: [DATABASE_URL, STRIPE_KEY]`, a bare name takes
  the value from the shell) and run `fnox exec -- docker compose up`.
- **Node `--env-file=.env`** errors on a missing file. Switch to
  `--env-file-if-exists=.env` (Node 22.9+) and run the script under `fnox exec --`.
- **Kamal 2 `.kamal/secrets`** lines like `KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD`
  need no change: run `fnox exec -- kamal deploy` and the variables are there.
- `rg -n '\.env\b'` over scripts, Procfiles, Dockerfiles and CI config for other readers.

### 6. Decide commit vs. ignore for `fnox.toml`

- **Solo repo:** commit `fnox.toml` (references + a project ID — no secret values) so the
  setup travels with the repo.
- **Repo shared with people who don't use fnox:** list `fnox.toml` in `.git/info/exclude`,
  not `.gitignore`, so it stays local and the shared repo gets no change from you.
- Either way, keep `.env*` ignored.

### 7. Verify, then remove the `.env`

The script's `--verify` does this. By hand, compare inside one process and print only the
verdict, never the value:

```bash
fnox list                                           # names, not values
fnox exec -- sh -c 'echo "${DATABASE_URL:+SET}"'    # presence check only
```

Only once every variable reports `same` (or a real secret resolves): delete the now-redundant
`.env`, and commit the `fnox.toml`/`mise.toml`/`.gitignore` changes.

## Guardrails

- **Never** put a secret *value* into `fnox.toml` or any committed file — only references.
- **Never print a secret**: no `printenv VAR`, `fnox get VAR` to the terminal, or
  `${VAR:-UNSET}` (that prints the value). Presence checks use `${VAR:+SET}`.
- The **access token is itself a secret**. Don't commit it, paste it into `fnox.toml`, or
  export it from a shell profile: hand it to the one command that needs it, as step 3 does.
- Confirm `fnox.toml` has no plaintext secrets before committing (`grep` for known values).
- If secret resolution fails, suspect the keychain first (locked, or no token stored), then
  an expired token. Do **not** fall back to writing a plaintext `.env`.

---

**Credit:** Adapted from [Nate Berkopec's `env-to-fnox` skill](https://github.com/nateberkopec/dotfiles/blob/main/files/home/.claude/skills/env-to-fnox/SKILL.md),
which targets 1Password; this version defaults to Bitwarden Secrets Manager.
