# Audit: laptop and accounts

An audit is a rerun, not a fresh plan. The checks live in one **checklist file** in the
person's own repo (a notes or sandbox repo, never this public one), and each audit updates it.

## Find or start the checklist

1. Look for the path in memory, then for an earlier `security/*checklist*.md` or
   `*security-plan*.md` in the person's notes or sandbox repo.
2. None: create `security/personal-security-checklist.md` there from the template below, and
   save its path to memory.
3. Rerun every row; tick it with the date and the observed value, so the next run can diff.
   Research only what is new since the last run (a new device, a new threat, a new install).

## Laptop checks

Read-only, no root unless marked. Root-only checks go to the person as one script.

- **Firewall:** read the config (`/etc/ufw/ufw.conf` `ENABLED=`), not the unit state.
  `ufw status verbose` needs root.
- **Listeners:** `ss -lntup` and anything not on loopback; `docker ps --format
  '{{.Names}} {{.Ports}}'` (published ports bypass ufw). Fix an unwanted one with
  `dev-hooks:expose-service`, whose audit for a second way in is the one home for that check.
- **Remote ways in:** `tailscale serve status`, `tailscale funnel status`, an sshd, Syncthing
  peers (the device names identify the phone).
- **Root boundary:** `id` (docker, input, sudo groups), NOPASSWD lines in `/etc/sudoers.d/`
  (root), root units whose `ExecStart` runs a user-owned file (`systemctl cat`), udev rules
  that give the user write on `/dev/uinput` (fake keystrokes into a sudo-warm terminal).
- **Updates:** which origins unattended-upgrades covers (third-party repos often aren't),
  `fwupdmgr security` (HSI level), and running kernel vs installed (`uname -r`).
- **Disk:** `lsblk -f` (LUKS, swap inside it), `mokutil --sb-state`.
- **Credentials:** SSH keys without a passphrase (`ssh-keygen -y -P '' -f <key> >/dev/null`
  succeeds only on an unprotected key and prints nothing), modes of credential files via
  `stat`, plaintext `.env` files (`fd -H -I '^\.env$'`, then `dev-hooks:env-to-fnox`), secret
  names exported into every process (names only: `env | cut -d= -f1 | rg -i
  'token|secret|key|pass'`).
- **Install cooldowns:** global release-age settings for npm, uv, pnpm and Bundler; the table
  lives in `dev-hooks:dev-env-setup`.
- **Browsers:** extension count per profile, stale profiles, saved logins (count hostnames
  only, never usernames or passwords), whether the browser offers to save passwords.
- **Agent config:** Claude Code allow rules that run arbitrary code (`Bash(find:*)`,
  `Bash(xargs:*)`, `Bash(* --help)`), and browser automation that launches unsandboxed (probe
  the renderer's `Seccomp`).
- **Backups:** a copy of the backup password off the laptop, and a dated test restore.

## Account checks (tiered)

Most of these need the person's eyes. Hand them over as STE steps and record the answers.

- **Tier 1, the recovery chain:** the email account that every other reset goes through
  (hardware key or passkey, recovery options, a recovery phrase on paper only), the password
  manager, the phone carrier (SIM PIN, the carrier login's 2FA, any port-out lock), the phone
  (theft protection, remote lock).
- **Tier 2:** each domain's registrar lock and expiry by RDAP (`curl -s
  https://rdap.org/domain/<domain> | jq '.status, .events'`; whois is often not installed) and
  mail records (`dig +short MX`, `TXT`, `TXT _dmarc.<domain>`); GitHub 2FA, keys and token
  scopes; services still on SMS codes that offer TOTP or a passkey.
- **Tier 3:** messenger registration locks, cloud bridges that can read SMS codes, an offline
  backup.

## Checklist template

```markdown
# Personal security checklist

Last run: YYYY-MM-DD. Sources: <links behind each tier>.

## Laptop
- [ ] Firewall enabled in config — YYYY-MM-DD: <observed>
- [ ] No unexpected non-loopback listener — YYYY-MM-DD: <list>
- [ ] …one line per check above

## Accounts
### Tier 1
- [ ] Recovery-chain email: <factor>, recovery phrase on paper — YYYY-MM-DD
### Tier 2
### Tier 3

## Open
- <finding> — <who acts> — <since>
```
