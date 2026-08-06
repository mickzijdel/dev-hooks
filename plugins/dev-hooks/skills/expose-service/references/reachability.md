# "It's deployed but I can't reach it"

Walk outward from the process. Stop at the first rung that fails — that rung is the bug, and
everything past it is noise. Guessing between rungs is what turns this into three rounds.

## Rung 1 — Is the process actually serving?

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://localhost:PORT/
```

Inside the container if it's containerised (`docker compose exec <svc> curl …`). A connection
refused here means the app never bound; check its own logs before touching any network config.

## Rung 2 — Is it bound where anything else can see it?

```bash
ss -lntp | grep ':PORT'
```

- `127.0.0.1:PORT` → loopback only. Invisible to the reverse proxy, to other containers, to
  everything off-box. Most "container is running but the proxy 502s" reports end here.
- `0.0.0.0:PORT` → all interfaces.
- A specific IP → reachable on that interface only, and **not** through cloud inbound NAT, which
  delivers only to wildcard binds.

For containers, check the published mapping too (`docker compose ps`): a port that is exposed
inside the compose network but not published is unreachable from the host's proxy.

## Rung 3 — Can the proxy reach the origin?

From the **proxy host**, not from your laptop:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://<origin-ip>:PORT/
```

`curl: (7) Failed to connect` from the proxy while rung 1 passed on the origin means it is
network, not application: security group / NSG, host firewall, a container on a different
network, or the wrong origin IP in the proxy config.

Verify the proxy's configured backend actually matches. Common mismatches: a stale IP after a
host rebuild, the wrong port, `https` where the origin speaks `http`, and a **renamed docker
volume or network** silently pointing the stack at fresh empty state.

## Rung 4 — Does the name resolve, to the record you meant?

```bash
dig +short app.example.com
curl -sSI --resolve app.example.com:443:<expected-ip> https://app.example.com/
```

- Fresh records take time. If you added the DNS entry minutes ago, that alone explains it — wait
  before changing anything else, or you'll "fix" it twice.
- Proxied (orange) returns CDN IPs; direct (grey) returns the origin. Which one you have changes
  whether edge protections apply at all.
- `--resolve` lets you test the origin and the edge separately over the same hostname. Use it to
  tell "the edge is broken" apart from "the origin is broken".

## Rung 5 — TLS

- Check the **origin** cert by IP; the browser padlock under a strict CDN mode shows the edge
  cert and stays green while the origin expires.
- A hard `400` immediately after enabling mutual-TLS origin pulls means that hostname isn't
  proxied — see `references/public-edge.md`.
- `526` / `502` from the edge with a healthy origin process points at the TLS leg between edge
  and origin, not at the app.

## Two whole-box failure modes worth checking early

If **everything** on a host broke at once — not one service — stop walking the ladder and check:

- **Port collision after a reboot.** Two daemons that coexisted at runtime can race at boot; the
  loser fails to bind and takes all its vhosts with it. See the contention section in
  `references/tailscale.md`.
- **A container stack restarted piecemeal.** Starting one container of a compose stack detaches
  it from the compose network, breaking service-name DNS between containers. Bring the whole
  stack up together.
