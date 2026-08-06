# Tailscale Serve and VIP Services

`tailscale serve` turns one tailnet node into a reverse proxy for anything it can reach. The
node dials the origin from its own stack, so **you do not need a subnet route** — advertising
one to reach a single web UI widens blast radius for nothing.

## Why it beats a VPN + IP for internal web UIs

Serve terminates a **real Let's Encrypt cert** on the tailnet side. Internal gear (UniFi,
Proxmox, EdgeOS, IPMI, NAS boxes) almost universally serves a self-signed cert; behind Serve
the browser is happy and the bad cert stays on the private side. Tell Serve to ignore it:

```bash
tailscale serve --bg --https=443 https+insecure://192.168.0.133:8443
```

`https+insecure://` applies to the **origin** leg only. Requires tailnet HTTPS certs enabled for
the tailnet (`CertDomains` non-empty in `tailscale status --json`).

## Per-service hostnames need VIP Services, not subdomains

MagicDNS names are **flat**. `unifi.<node>.<tailnet>.ts.net` cannot work — certs are issued for
a node's own FQDN and there is no subdomain layer under it. For several services behind one
proxy node, use VIP Services, which give `https://<name>.<tailnet>.ts.net`:

1. **Define the Service in the admin console first** (Services → Define Service): name, port
   443, description. The name becomes the hostname.
2. Advertise it from the proxy host:
   `tailscale serve --service=svc:<name> --bg --https=443 <origin>`
3. **Approve the host** in the console under that Service's *Hosts* tab.

### Traps, all of which cost a debugging round the first time

- **The console lags.** A defined Service shows *0 hosts* until the control plane next polls the
  node. Nothing is broken — wait and reload. Confirm the poll landed with
  `journalctl -u tailscaled | grep vip-services` (look for `c2n: GET /vip-services received`).
- **`tailscale serve status` does not list services.** Use `tailscale serve status --json` and
  read `.Services`. The plain output will convince you nothing is configured.
- **Legacy web UIs that send absolute `http://` redirects break.** Serve rewrites the host but
  keeps the scheme, so a redirect to `http://<host>/login` lands on port 80 where nothing
  listens. Fix by adding an HTTP listener alongside the HTTPS one:
  `tailscale serve --service=svc:<name> --bg --http=80 <origin>`. Traffic on 80 reaches the VIP
  even when the Service definition only lists 443.
- **Never use `tailscale up` to change an existing node's config.** It resets every flag you
  omit and has locked people out of their own boxes. Use `tailscale set` for individual prefs
  (`tailscale set --advertise-routes=` to drop routes, `--ssh` to toggle SSH).

## Port contention with an existing reverse proxy

Running `tailscale serve --https=443` on a box that already serves 443 (Nginx Proxy Manager,
Caddy, Traefik) is **order-dependent, and the failure mode is a total outage**:

- `tailscaled` binds a specific address (`100.x.y.z:443`) with `SO_REUSEADDR`.
- A container's `docker-proxy` binds wildcard `0.0.0.0:443` **without** it.

They coexist only if the wildcard binder goes first. A `--bg` serve is restored early at boot,
wins the race, and every site on the box goes down. Two things follow:

- **Do not use `--bg` on a contended port.** Run Serve from a systemd unit that waits for the
  other listener, then runs in the foreground with `Restart=always`.
- **Binding the proxy to a specific IP to dodge the clash does not work** behind cloud inbound
  NAT (Azure, and load balancers generally) — NAT only delivers to a `0.0.0.0` bind, and a
  specific-IP bind gets you an edge-level 5xx instead.

## Reboot survival

Serve config and service advertisements persist in `/var/lib/tailscale/tailscaled.state`
(serve config under `_serve/<profile>`; `AdvertiseServices` at the **top level** of
`profile-<id>`, not inside its nested `Config` key, which holds private keys). Host approval is
server-side, so **a restart needs no re-approval** — verify rather than assume if it matters.

Harden the daemon when it is the only route in:

```ini
# /etc/systemd/system/tailscaled.service.d/override.conf
[Service]
Restart=always
RestartSec=5
StartLimitIntervalSec=0   # else systemd gives up permanently after repeated fast restarts
```

`Restart=` cannot catch a **hang** — a live PID whose `tailscale status` never answers. Add a
short timer that probes for a *response* and restarts on either condition. Make it refuse to
undo a human: `BackendState=Stopped` (someone ran `tailscale down`) and `NeedsLogin` (expired
key) should log and exit, never restart, or the watchdog will fight the operator.

After a full host reboot, expect services whose origins are guests on that host to 502 for a
minute or two while the guests boot. Confirm the guests are set to start on boot.
