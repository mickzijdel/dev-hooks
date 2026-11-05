---
name: personal-security
description: "Use for security work on your own laptop, servers or accounts, not code: a hardening pass or re-run of a security audit, \"am I affected by\" a CVE or a flaw in the news, a pasted security warning to check against this machine, or vetting an app, extension, plugin or .deb before installing it. Not for a PR or diff (/security-review), a vulnerable package in an app (dependency-upgrade) or fact-checking a draft (fact-check)."
---

# Personal security

Security work on the person's own machines and accounts. Four entry points share one method:
pick the reference for the request, and apply the method to every step in it.

| The person… | Read |
|---|---|
| wants a hardening pass, or the last audit re-run | `references/audit.md` |
| names a CVE or a flaw in the news: "am I affected", "mitigate before the patch" | `references/vuln-response.md` |
| pastes a third-party warning, advisory or viral post | `references/advisory-triage.md` |
| wants an app, extension, plugin or package vetted before install, or its updates reviewed | `references/third-party-install.md` |

**Start from memory.** Earlier audits, the checklist file's path, and per-host traps (a server
that needs a clean database stop before a reboot, an old firewall tool, a past boot failure,
a host someone else now runs) live in the person's memory. Read them first. When a file on disk
and a memory note disagree, the newer file wins: the person edits it between sessions.

## The method

1. **Primary sources over news.** The vendor's security tracker or errata, the project's
   release feed and changelog, the upstream commit. News, threads and fetched summaries are
   leads; read the changelog text itself, because a summary can put a fix in the wrong
   version. Check each distro you run on its own: an "Ubuntu flaw" in the upstream kernel hits
   every distro.
2. **A positive control for every lookup.** Before an empty answer counts, run the same query
   against something known to match: an older CVE in the errata API, a test host that should
   fail, a canary file. A missing tool also answers "not found". No control, no conclusion.
3. **A live probe before any verdict.** Code and config say what should happen; only a probe
   says what does. Code reading has called a browser sandboxed while `/proc/<pid>/status`
   showed `Seccomp: 0`, and `systemctl is-active ufw` has said active while the config held
   `ENABLED=no`. Probe traps: `pgrep -f`/`pkill -f` inside a compound shell command match the
   agent's own shell (use `pgrep -x` or a pid), and Chrome rewrites its `/proc/<pid>/cmdline`
   with spaces, not NULs.
4. **Never read a credential file.** List what is there with the tool's own status command
   (`gh auth status`, `ssh-add -l`, `rclone listremotes --ask-password=false`,
   `gcloud auth list`, `bws secret list | jq -r '.[].key'`), and presence and modes with
   `stat -c '%a %U %n'`. From an app's settings print only the keys you need. When you mask a
   secret line, classify its right-hand side (a literal or an env lookup) before you report
   it. If a value reaches the transcript, say so and tell the person to rotate it.
5. **Read-only until the person chooses.** Report ranked findings; change nothing on their
   machines or accounts without a yes. Hand root and remote-root work over unless they
   explicitly hand it to you. Before a firewall or network change on a remote host, arm a
   recovery first (`dev-hooks:expose-service` §2).
6. **Hand over steps in ASD-STE100.** One action per step, absolute paths, the exact `sudo`
   command, a variant per host where they differ, and a check the person runs after that says
   pass or fail (a script that exits 0 when protected beats "look at the output").
7. **Leave it findable.** Per-host facts and traps go in memory; repeatable checks go in the
   living checklist file (`references/audit.md`); a check you will rerun becomes a script.

A security bug you find in someone else's tool goes upstream through `dev-hooks:upstream-bug`,
by its private channel. A fix blocked by a package manager's release-age cooldown:
`dev-hooks:dependency-upgrade` has the bypass for one urgent package.

## Done when

- Every verdict rests on a live probe, or says why no probe was possible.
- Every empty lookup has its positive control beside it.
- No credential value was printed, or the person was told which one to rotate.
- The person has ranked findings, and STE steps with a pass/fail check for each thing only
  they can do.
- New facts and host traps are in memory, and the checklist file is updated if one was used.
