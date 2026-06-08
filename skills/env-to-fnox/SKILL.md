---
name: env-to-fnox
version: 1.1.0
description: |
  Migrate a project's plaintext .env file to fnox, a secret manager that stores
  only *references* in a committed fnox.toml and resolves real values from a vault
  at run time. Use when a repo has secrets in .env (or .env.local) and the user
  wants them out of plaintext, when setting up secrets for a new project, or when
  the user mentions fnox, Bitwarden Secrets Manager, bws, or "stop committing my
  .env". Defaults to the Bitwarden Secrets Manager provider; also supports
  1Password, age, AWS/Azure/Vault, and the OS keychain.
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

## When to use

- A repo has real secrets sitting in `.env` / `.env.local`.
- The user wants secrets out of plaintext / out of version control.
- Setting up secrets management for a new project.

## Workflow

Work through these in order. Verify a real secret resolves before deleting anything.

### 1. Analyze the existing `.env`

Read the `.env` (and `.env.local`, `.env.*`) and **categorise** each entry:

- **Real secrets** — API tokens, DB passwords, private keys, OAuth client secrets, signing
  keys. These move into the vault.
- **Non-secret config** — ports, hostnames, feature flags, public keys, `NODE_ENV`. These do
  *not* belong in a vault; keep them as plain defaults in `fnox.toml` or `mise.toml`.

List what you found and which bucket each falls into before touching the vault.

### 2. Install the tools and authenticate

```bash
mise use -g fnox bitwarden-secrets-manager   # installs fnox + the bws CLI
fnox --version && bws --version              # verify
```

Secrets Manager auth is a **machine-account access token**, not a login. One-time, in the
[Secrets Manager web console](https://bitwarden.com/help/secrets-manager-quick-start/):
create a **project**, create a **machine account**, grant it access to the project, and
generate an **access token** (shown once). Then:

```bash
export BWS_ACCESS_TOKEN="<your-access-token>"   # fnox and bws both read this
```

> The token only decrypts/edits the secrets in its project — it can't touch a personal
> password vault. Keep it out of committed files (see Guardrails for caching it safely).

### 3. Store the secrets in the vault (this provider is read **and** write)

Unlike the Password Manager provider, `bitwarden-sm` can write — so fnox creates secrets for
you, and `bws` can create/edit them directly. Either works:

```bash
# Via fnox (also writes the reference into fnox.toml):
fnox set DATABASE_URL "postgres://..." --provider bws --key-name "database-url"

# Or via the bws CLI directly:
bws secret create database-url "postgres://..." <PROJECT_ID>   # create
bws secret list                                                # find a secret's ID
bws secret edit <SECRET_ID> --value "postgres://new..."        # edit
```

Use clear, stable **key names** (e.g. `database-url`) — `fnox.toml` references secrets by key.

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
DATABASE_URL = { provider = "bws", value = "database-url" }
STRIPE_KEY   = { provider = "bws", value = "stripe-api-key" }

# Non-secret config stays as plain defaults (no provider):
# PORT = { value = "3000" }
```

Append `/note` or `/key` to a value for those fields (e.g. `value = "database-url/note"`).

> **Password Manager variant:** for the personal-vault provider instead, use
> `bw = { type = "bitwarden" }`, reference items by name (`value = "ItemName"` →
> the item's password field, or `"ItemName/fieldName"`), and populate the vault yourself —
> that provider is **read-only**, so `fnox set --provider bw` would only inline the value
> (don't). Auth there is `export BW_SESSION=$(bw unlock --raw)`.

### 5. Wire it into the run-time

- **mise projects (preferred):** in `mise.toml`, replace `.env` loading with
  ```toml
  [env]
  _.source = "fnox export"
  ```
  Secrets load when the shell enters the project. `BWS_ACCESS_TOKEN` must be in the
  environment; if `fnox export` errors with an auth message, the token is missing/expired.
- **Non-mise projects:** run commands through `fnox exec -- <cmd>`, e.g.
  `fnox exec -- npm run dev`.

### 6. Decide commit vs. gitignore for `fnox.toml`

- **Solo repo:** commit `fnox.toml` (references + a project ID — no secret values) so the
  setup travels with the repo.
- **Repo shared with people who don't use fnox:** add `fnox.toml` to `.gitignore` so it stays
  local and collaborators are unaffected.
- Either way, keep `.env*` gitignored.

### 7. Verify, then remove the `.env`

```bash
fnox list                          # shows configured secrets (names, not values)
fnox exec -- printenv DATABASE_URL # confirm the value resolves inside the process
```

Only once a real secret resolves correctly: delete the now-redundant `.env`, and commit the
`fnox.toml`/`mise.toml`/`.gitignore` changes.

## Guardrails

- **Never** put a secret *value* into `fnox.toml` or any committed file — only references.
- The **access token is itself a secret**. Don't commit it or paste it into `fnox.toml`. To
  avoid a plaintext token in your shell profile, cache it in the OS keychain via fnox's
  global config (the keychain provider must be registered there first, or `set` errors with
  "Provider 'keychain' not found"):
  ```bash
  fnox init -g --skip-wizard                 # once, if no global config exists
  fnox provider add keychain keychain -g     # register the provider globally
  fnox set -g BWS_ACCESS_TOKEN "<token>" --provider keychain   # set takes -g; get does not
  ```
  Then load it in your shell profile (only a reference is stored in config; the value lives in
  the keychain): `export BWS_ACCESS_TOKEN="$(fnox get -c ~/.config/fnox/config.toml BWS_ACCESS_TOKEN)"`.
- Confirm `fnox.toml` has no plaintext secrets before committing (`grep` for known values).
- If secret resolution fails, suspect a missing/expired `BWS_ACCESS_TOKEN` first — do **not**
  fall back to writing a plaintext `.env`.

---

**Credit:** Adapted from [Nate Berkopec's `env-to-fnox` skill](https://github.com/nateberkopec/dotfiles/blob/main/files/home/.claude/skills/env-to-fnox/SKILL.md),
which targets 1Password; this version defaults to Bitwarden Secrets Manager.
