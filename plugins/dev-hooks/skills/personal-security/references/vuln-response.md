# Vulnerability response: "am I affected?"

A named CVE or a flaw in the news, and the person's laptop and servers. Work every host, not
only the one in the headline.

1. **Identify the component** and whether the bug is upstream (kernel, OpenSSL, glibc: every
   distro you run) or in one distro's packaging. Name each host's distro and release.
2. **Fix status per distro and release**, from the vendor: the Ubuntu CVE tracker, the Debian
   security tracker, Red Hat's CVE page and RHSA, the Rocky or Alma errata API, Alpine secdb.
   Run the positive control: the same query for an older CVE of the same component must
   return a hit. Rebuilds lag RHEL by hours to days, and RHEL's fixed build predicts theirs.
   "In progress" or "pending": read the changelog of the candidate (`-proposed`) package for
   the fix's own commit title, and the release calendar for its date.
3. **Running version per host:** `uname -r` or the package version, and installed vs running
   (an installed fix waits for a restart or reboot). `dnf updateinfo list --cve <id>` on RPM
   hosts.
4. **Exposure:** what reaches the vulnerable code: listeners and their protocol (`ss -lntup`,
   `ss -lM` for MPTCP), the sysctl or config switch that gates it, and containers. Containers
   share the host kernel, so images need no rebuild for a kernel bug, but a host filter does
   not cover traffic inside a container's own network namespace.
5. **Interim mitigation:** the narrowest rule that stops the attack traffic and nothing
   legitimate (an nft rule, a sysctl, a config switch). Test it without root in a private
   network namespace (`unshare -rn`): baseline reachable, rule loaded and dropping, rule
   removed and reachable again. Ship it with a check script that needs no root and exits 0
   when protected. Persist it with a oneshot unit, and confirm it after a reboot. Check the
   syntax against the oldest host's tools (an older nft wants a numeric priority).
6. **Per-host handover:** pull each host's traps from memory (a database that needs a clean
   stop before a reboot, low RAM, a past boot failure, another admin's update and reboot
   window, whether it auto-applies updates). One STE block per host, ending with the check
   script. Before a firewall change on a remote host, arm a recovery
   (`dev-hooks:expose-service` §2).
7. **Keep the filter after the patch** when it drops only traffic nothing legitimate sends:
   removing it costs a step and gains nothing. Note it where the next admin of that host looks.
8. **Watch for the fix** when it isn't out: a timer that polls the vendor source, alerts once
   per release that ships it, and disables itself when all are out. Test it end to end with
   the older CVE from step 2.
9. **Close:** each host runs the fixed version (`uname -r` after the reboot) and its check
   script still passes.

A host the person no longer runs: answer from outside (an `ssh-keyscan` banner names the
OpenSSH package and so the release) and hand its owner a note. Don't log in, even if invited.
