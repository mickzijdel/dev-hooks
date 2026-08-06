# Public edge: tunnels, Access, origin hardening, certs

## The failure that matters most: the edge gate is not an origin gate

Cloudflare Access (and any edge SSO) is enforced **at Cloudflare**. If the origin still answers
on 443, anyone who learns the origin IP skips the gate entirely:

```bash
curl -sk --resolve app.example.com:443:<origin-ip> https://app.example.com/api/
```

A `200` there means the identity gate is decorative. Assume the origin IP is discoverable — it
leaks through SSH configs, wiki pages, cloud IP-range scans, and Shodan/Censys fingerprinting of
whatever software you run. Proxied DNS hides it from a casual lookup and nothing more.

**Close it, biggest impact first:**

1. **Firewall inbound 443 to the CDN's published ranges** (cloud NSG / security group). Leave
   **80 open** if anything on the box renews via HTTP-01 or webroot — port 80 typically only
   serves redirects, so this costs nothing.
2. **Authenticated Origin Pulls (mTLS)** — the origin demands a client cert only Cloudflare
   presents. In Nginx terms, per host:
   ```nginx
   ssl_client_certificate /path/to/origin-pull-ca.pem;
   ssl_verify_client on;
   ```
   **Only works for proxied (orange-cloud) hostnames** — Cloudflare must be in the path to
   present the cert. A grey-clouded or CDN-paused hostname gets a hard `400` the moment you turn
   this on. Enumerate every hostname on the box before enabling it.
3. **Keep admin panels off the public path entirely** — serve them tailnet-only (see
   `references/tailscale.md`) rather than gating them.

### Audit for the *second* way in

Closing the obvious route is not the same as closing the route. Check all of these:

- **Deleting a DNS record does not delete the proxy entry.** The reverse proxy still serves that
  vhost at the origin with the right `Host` header. Delete the proxy host, not just the record.
- **Another vhost pointed at the same backend.** A forgotten hostname forwarding to
  `localhost:<admin-port>` is a full second admin login, and if it is grey-clouded it has no
  edge protection at all. Enumerate proxy entries by *backend*, not by name.
- **The admin port itself.** Publishing it on `0.0.0.0` may or may not be reachable from the
  internet — test rather than reason about it, and prefer binding to loopback or the tailnet IP.

## Cloudflare Tunnel

Use when you want a public URL with **no inbound port** at all: the origin dials out, so there
is no origin IP to firewall and the bypass above cannot exist. Pair with Access for identity.
Costs: another daemon to keep alive on the origin (§5 of the SKILL applies — persistence,
restart, ordering), and the tunnel token is a credential — treat it like one, keep it out of
argv and out of committed files.

Prefer a tunnel over "reverse proxy + firewall rules" when the origin is somewhere you cannot
control the network layer, or when the origin IP must not be discoverable at all.

## Certificates

- **Under Full (strict), the browser padlock is the *edge* cert.** It stays green long after the
  origin cert expires — until the CDN starts returning 526. **Check the origin directly**, by IP,
  bypassing the CDN. Alerting on the public URL will not warn you.
- **Two issuers on one domain fight.** An automatic issuer (cPanel AutoSSL, certbot) stands down
  when a valid cert from another source already covers the name, then the manual one lapses and
  nobody notices. If you install a manual cert, exclude that name from the automatic issuer.
- **CDN proxying does not break HTTP-01.** A common false belief. `/.well-known/acme-challenge/`
  is proxied byte-identical and uncached, provided the origin exempts it from any HTTPS
  redirect. Validate the actual failure before blaming the CDN — the real cause is usually the
  competing-issuer case above.
- **Expect noise from service subdomains.** cPanel-style hosts try `mail.`, `cpanel.`,
  `webmail.`, `autodiscover.` and friends every run and fail DCV because they have no DNS.
  Exclude them, or a genuine failure will never be visible in the report.
- **Emergency lever if an origin cert does lapse:** drop Full (strict) → Full. Seconds, keeps
  traffic encrypted, buys time to fix the origin properly. Put it back afterwards.

## Reverse-proxy operations

- **Never `docker start` one container of a compose stack.** It rejoins without the compose
  network, so service-name DNS between containers breaks (`getaddrinfo EAI_AGAIN db`). Always
  `docker compose up -d` from the stack directory; `down` + `up` to rebuild the network.
- **Script against the proxy's API, not its database or key files.** Mint a short-lived token via
  its documented login endpoint. Reading signing keys off disk to forge one is both fragile and
  indistinguishable from an attack.
- **Pass credentials over stdin**, never argv (visible in `ps`) and never a file you then forget
  to delete.
