# 07 — Domain, DNS, and Caddy

## Purpose

One set of URLs that work identically on the LAN and over Tailscale, with real
HTTPS certificates and nothing exposed to the internet.

## Prerequisites

- Doc 06 complete
- A registered domain (examples below use `example.nz`)
- Cloudflare account with the domain's nameservers pointed at it

## The split-DNS model

This is the non-obvious part, so it's worth understanding before you configure it.

```
Client asks for jellyfin.example.nz
│
├── On the LAN     → AdGuard on enma rewrites → 192.168.1.10  (jigoku LAN IP)
└── On Tailscale   → Tailscale split DNS → AdGuard → 100.x.x.x (jigoku TS IP)

Either way: Caddy answers on 443 with a valid cert.
```

The certificate is issued via **DNS-01**, meaning Let's Encrypt validates by
checking a TXT record in Cloudflare rather than connecting to your server. So
you get trusted certs on a box that has no inbound ports open at all.

## Steps

### 1. Cloudflare API token

Cloudflare dashboard → My Profile → API Tokens → Create Token → **Edit zone
DNS** template. Scope it to your zone only. Copy the token.

Store it encrypted:

```bash
sops secrets/jigoku.enc.yaml
```

```yaml
cloudflare_api_token: "your-token-here"
```

### 2. DNS records

You need **no public A records** for this to work. The DNS-01 challenge only
writes temporary TXT records. Optionally, add a private A record for
documentation purposes.

### 3. Caddy

Caddy needs a build including the Cloudflare DNS plugin — the compose file uses
a prebuilt image with it baked in.

```bash
cd /opt/stacks/caddy
cp .env.example .env      # fill in DOMAIN and CF token reference
docker compose up -d
docker compose logs -f caddy
```

The Caddyfile lives at [`config/caddy/Caddyfile`](../config/caddy/Caddyfile).

### 4. AdGuard DNS rewrites

Once enma is up (doc 13), add a wildcard rewrite in AdGuard:

| Domain | Answer |
|---|---|
| `*.example.nz` | `192.168.1.10` |

LAN clients now resolve every service to jigoku's LAN address.

### 5. Router DNS

Set your router's DHCP to hand out enma's IP as primary DNS. See doc 13 for
the secondary-DNS tradeoff before you do.

## Service map

| Hostname | Service | Reachable by |
|---|---|---|
| `jellyfin.example.nz` | Jellyfin | everyone incl. `tag:guest` |
| `requests.example.nz` | Jellyseerr | trusted + guests |
| `books.example.nz` | Audiobookshelf | trusted |
| `home.example.nz` | Homepage | trusted |
| `sonarr.example.nz` | Sonarr | trusted only |
| `radarr.example.nz` | Radarr | trusted only |
| `prowlarr.example.nz` | Prowlarr | trusted only |
| `bazarr.example.nz` | Bazarr | trusted only |
| `sab.example.nz` | SABnzbd | trusted only |
| `qbit.example.nz` | qBittorrent | trusted only |
| `dockge.example.nz` | Dockge | trusted only |
| `logs.example.nz` | Dozzle | trusted only |

## Verify

- [ ] `curl -I https://jellyfin.example.nz` returns 200 with a valid cert
- [ ] `docker compose logs caddy` shows certificates obtained, no errors
- [ ] From the LAN, `dig jellyfin.example.nz` returns 192.168.1.10
- [ ] From mobile data on Tailscale, the same hostname returns the 100.x address
- [ ] `sudo ss -tlnp | grep :443` shows only Caddy
- [ ] A `tag:guest` device gets 403 on `sonarr.example.nz`

## Rollback

```bash
cd /opt/stacks/caddy && docker compose down
```

Services remain reachable on their raw ports over Tailscale, so nothing is
lost — you just lose the nice URLs while you debug.

## Notes

### Guest restriction needs both layers

Tailscale ACLs restrict by IP and port. But Caddy serves every hostname on the
same port 443, so network-layer ACLs alone would let a guest who guesses
`sonarr.example.nz` straight through. The Caddyfile therefore also matches on
source IP range and returns 403 for non-Jellyfin hostnames from guest
addresses. Belt and braces — see the `@guests` matcher in the Caddyfile.

### The router breaks this until AdGuard exists

Most consumer routers — including the SmartModem2 here — run DNS rebinding
protection and silently discard answers that point a public domain at a private
address. Cloudflare returns `192.168.1.10` correctly; the router throws it away.

Symptom: `dig example.com @1.1.1.1` works, `dig example.com` returns nothing.

This router exposes no way to change the DNS it advertises, so the fix is
AdGuard doing local rewrites (doc 13). Until then, manual DNS per device is the
only workaround — and note Windows prefers the router's **IPv6** DNS over a
manually set IPv4 one, so IPv6 has to be disabled on the adapter for the
override to take effect.

### Certificate renewal

Caddy renews automatically at roughly two-thirds of the lifetime. It needs the
Cloudflare token to remain valid — if you rotate it, update the secret and
restart Caddy. Uptime Kuma (doc 13) monitors certificate expiry so a silent
renewal failure gets noticed.

### Why not Tailscale Serve

`tailscale serve` gives HTTPS on `*.ts.net` names for free. It's a legitimate
alternative, but those names only resolve over Tailscale — and the Samsung TV
can't run Tailscale. You'd end up with two addressing schemes. The domain
avoids that.
