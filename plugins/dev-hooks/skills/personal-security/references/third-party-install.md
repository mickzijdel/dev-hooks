# Third-party install: vet it, then keep updates reviewed

Before any install, tell the person what privilege it needs (a root maintainer script, a file
capability, keystroke access, a D-Bus service, a browser native-messaging manifest) and what
that privilege really grants. `cap_dac_override` reads every file on the machine; it is not
"keyboard access".

Take the **light path** for one package. Take the **heavy path** for an app with privileged
parts or a plugin store, or when the person wants its updates reviewed from now on.

## Light path: one package

1. Download into its own empty directory: `gh release download <tag> -R <owner>/<repo>
   -p '<asset>' -D <dir>`.
2. Verify the digest GitHub lists for that asset: `gh api
   repos/<owner>/<repo>/releases/tags/<tag> --jq '.assets[] | select(.name=="<asset>")
   | .digest'` against `sha256sum`. Check a published signature too.
3. Inspect without installing: `dpkg-deb -I` (depends, maintainer), `dpkg-deb -c` (setuid
   files, `/etc`, systemd units), `dpkg-deb -e <deb> <dir>` and read every maintainer script:
   a postinst may grant a capability itself.
4. `apt-get install --simulate ./<deb>` without root proves the dependencies resolve on this
   release.
5. Read option names and defaults in the upstream source, not a docs summary. Write the
   config before first start, so defaults (sample content, a hotkey) never land.
6. Check conflicts: its default hotkeys against the desktop's, and its autostart target (a
   user unit on `default.target` with lingering starts before the graphical session and
   crash-loops; bind it to `graphical-session.target`).
7. Hand over the exact `sudo` command with the absolute path.
8. Probe after install: `getcap`, the running threads' `CapEff` in `/proc/<pid>/task/*/status`,
   `aa-status`. A broad capability earns a confinement profile. Build it from `strace` of a
   throwaway instance: without auditd the kernel throttles AppArmor messages, so learning mode
   undercounts.

## Heavy path: an app with privileged parts or a store

1. **One reviewer per trust boundary** (the core app, a privileged shell extension, the plugin
   store), each reviewing the exact artifact that will run (the AppImage, the extension zip,
   the store tarball), not the repo. Spot-check every High claim yourself with a probe.
2. **First-start behaviour,** which code review misses: start it and watch for a minute.
   Background indexers and crawlers (network or FUSE mounts under HOME), plaintext caches and
   files outside its encrypted store, what it writes into other apps' config (native-messaging
   manifests, autostart entries), and network calls. `fd --changed-within 5min . ~`, `ss`,
   `du` on its cache dirs.
3. **Fail-closed config guard:** an `ExecStartPre` check that refuses to start when the config
   fails to parse or a security setting has reverted.
4. **Neutralise upstream auto-updates** (app self-updaters; the desktop's staged extension
   updates).
5. **Reviewed update gate:** a timer fetches each new release, runs integrity checks and
   mechanical tripwires the verdict can't override (sensitive files touched, new permissions,
   a diff too large to review), then a tool-less, isolated `claude -p` review of the diff.
   Auto-apply only a clean pass, and only if the person agreed; otherwise hold it with a
   report and an apply command. Anything that needs `sudo` is always held. Keep a rollback.
6. **Write down** the accepted risks and the uninstall steps (including what it wrote into
   other apps' config) in the install's README.
