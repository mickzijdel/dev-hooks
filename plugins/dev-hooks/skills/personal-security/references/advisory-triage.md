# Advisory triage: a pasted warning

Someone else's security warning, advisory or viral post ("stop and fix this today"), and the
person wants to know two things: is it true, and does it affect this machine. Answer in that
order, briefly. A draft the person wrote is `fact-check`'s job, not this one.

1. **Claims table.** One row per claim: the claim, the primary source checked (vendor release
   feed, upstream issue or commit, the researchers' own page and data files), a verdict
   (true, false, overstated, unverified), and seen or inferred. A claim with only secondary
   sources stays unverified.
2. **Local inventory.** Every install that touches the risk, not only the obvious one. For a
   CA or TLS problem: the system store, each Node version, Bun, Java's `cacerts`, certifi in
   each venv, Electron apps, flatpak runtimes, snaps with a bundled runtime. For a browser
   claim: every Chromium a tool launches, bundled ones included. Sources: `command -v`,
   `mise ls`, `flatpak list`, `snap list`, venvs under the repos.
3. **Live probe of each risk,** with a control that should come out the other way: the
   researchers' test host (a fixed client must reject it), `chrome://sandbox` or the renderer's
   `/proc/<pid>/status` `Seccomp` line, the actual cert store a tool loads. Where a tool can't
   be probed (Chromium blocks bad intermediates by key hash), judge it by version and say so.
4. **Ranked fixes:** by exposure and ease. For each interim override (an env var such as
   `NODE_OPTIONS=--use-openssl-ca` or `SSL_CERT_FILE`), probe which tools it fixes and list
   those it doesn't: bundled stores, flatpak runtimes and snaps often ignore it. A fix script
   gets `--dry-run` and `--verify-only` modes, and the verify mode reruns step 3.
5. **Write the answer:** real or not, affected or not, what to do now, what can wait. Record the
   inventory and what is still open in memory, so the next session checks the remainder.
