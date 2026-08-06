---
name: expose-service
description: |
  Make a service running on an internal or private host reachable — over Tailscale, a
  Cloudflare Tunnel, or a public reverse proxy — and keep it reachable after a reboot. Use on
  "expose X", "give me access to the admin panel", "put this behind a URL", "set up a tunnel
  to", "serve it on tailscale", "I can't reach it from outside", or when a just-deployed
  service 502s, is unreachable, or throws a cert warning. Also for the reverse — auditing
  whether something exposed is reachable by a path you did not intend. NOT a hosting or
  deployment decision (where the app should run); this starts once it runs somewhere.
---

# Exposing an internal service

Four decisions, in order: **who may reach it**, **how you avoid locking yourself out**, **what
proves it works**, and **what happens on reboot**. Skipping the second and fourth is how a
five-minute change turns into a trip to the server room.

## 1. Pick the exposure

Pick the narrowest row that satisfies the audience. Widening later is cheap; narrowing after
people have bookmarked a URL is not.

| Audience | Mechanism | Gives you |
|---|---|---|
| Just you, right now, once | `ssh -L` local forward, or `ssh -D` + `curl -x socks5h://` | Nothing persistent to clean up or forget |
| You + tailnet members | **Tailscale Serve** on a proxy node | Real LE cert, no port opened, origin never exposed |
| Same, but several services want clean names | **Tailscale VIP Services** (`svc:<name>`) | `https://<name>.<tailnet>.ts.net` per service, one proxy node |
| Anyone with an identity you can gate | **Cloudflare Tunnel + Access** | Public URL, no inbound port, SSO in front |
| Genuinely public | Reverse proxy + real cert at a public edge | Full control, and full responsibility for hardening |

Two rules that override the table:

- **A proxy node does not need a subnet route.** If the proxy dials the origin from its own
  network stack, routing the whole subnet buys nothing and widens blast radius. Don't advertise
  a subnet just to reach one web UI.
- **An identity gate at the edge is not a gate on the origin.** Cloudflare Access is enforced
  by Cloudflare. If the origin IP still answers on 443 with the right `Host` header, the gate
  is decorative. See `references/public-edge.md` — this is the single most common real hole.

## 2. Before you cut your own access

If the change can drop your SSH session, your tunnel, or the daemon you are reaching through —
**arm the recovery first, then detach the disruptive command**:

```bash
systemd-run --unit=rescue-net --on-active=240 /path/to/known-good-restore.sh   # arm FIRST
systemd-run --unit=apply-change --on-active=3 /path/to/change.sh              # then detach
```

Detaching matters: a command run in your SSH session dies with the session, often halfway.
Clean up afterwards with `systemctl stop <unit>.timer` and `systemctl reset-failed <unit>.service`.

Apply this to: restarting the daemon that carries your only route in, firewall/NSG rules,
`tailscale` pref changes, and reverse-proxy config reloads on the box you are proxied through.

## 3. Wire it

Read the reference for the mechanism you picked — each carries the traps that cost real
debugging time, not just the happy path:

- `references/tailscale.md` — Serve, VIP Services, `tailscale set` vs `up`, port contention
- `references/public-edge.md` — Tunnels, Access, origin bypass, Authenticated Origin Pulls, certs
- `references/reachability.md` — the triage ladder when it doesn't work

## 4. Prove it reaches

Never report success from the layer you just changed. Walk **outward**, one rung at a time, and
stop at the first rung that fails — that rung is the bug:

1. On the origin host: `curl -sS -o /dev/null -w '%{http_code}\n' localhost:PORT`
2. Is it bound where the proxy can see it? `ss -lntp | grep PORT` — `127.0.0.1:PORT` is
   invisible to anything off-box, including a container's own proxy
3. From the proxy host: `curl <origin-ip>:PORT`
4. From outside, by name: DNS resolving, and to the record you meant (proxied vs. direct)
5. TLS: check the **origin** cert directly by IP, not the browser padlock

Each rung is a different failure; guessing between them is what makes this take three rounds.

## 5. Make it survive a reboot

Ask these three explicitly — a service that works until the next power cut is not done:

- **Does the config persist?** Ephemeral `serve`, a foreground tunnel, a hand-run container
  all vanish. Check the persisted state, don't assume.
- **Does the daemon come back, and come back *working*?** `Restart=always` catches a crash but
  **not a hang**. If the daemon is your only route in, add a watchdog that probes it for a
  *response*, not just for a running PID — and have the watchdog refuse to undo a deliberate
  human action (an explicit "down", an expired key) so it can't fight you.
- **What is the boot ordering?** Two things binding the same port, or a proxy starting before
  the backends it fronts, both produce "worked yesterday, broken after reboot". Expect brief
  502s while backends come up; expect a hard outage if two listeners race for a port.

## 6. Write it down where the next person looks

One line per exposed service — **URL, origin, mechanism, and how to add or remove another**.
Without the last part this skill gets re-derived per service. Facts specific to one estate
(hostnames, IPs, which node proxies) belong in memory or that project's wiki; the procedure
belongs here.

## Done when

- Reached from a client that is **not** the host you configured, and not through your SSH session
- Every rung in §4 checked, or the reason a rung was skipped stated
- Daemon restarted (or the host rebooted) and the service came back without hand-holding
- No unintended second path in: origin IP with a `Host` header, a stale DNS record, a leftover
  proxy entry, a grey-clouded hostname pointing at the same backend
- The URL, its origin, and the add/remove procedure recorded somewhere the next person reads
