# 06 — Tailscale and ACLs

## Purpose

Private network access to jigoku and enma from anywhere, with guest devices
restricted to Jellyfin only.

## Prerequisites

- Doc 05 complete
- A Tailscale account (free tier covers up to 100 devices)

## Steps

### 1. Install on jigoku

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh=false --accept-routes
tailscale ip -4
tailscale status
```

### 2. Disable key expiry for servers

In the admin console, find `jigoku` and `enma` → **Disable key expiry**.
Otherwise they drop off the tailnet every 180 days, usually while you're away.

### 3. Enable MagicDNS and HTTPS

Admin console → DNS → **Enable MagicDNS**, then **Enable HTTPS**. This gives
each node a name like `jigoku.your-tailnet.ts.net` and lets Tailscale issue
real certificates for it.

### 4. Split DNS for the domain

Admin console → DNS → **Nameservers** → Add nameserver → Custom, pointing at
enma's Tailscale IP (`100.92.26.115`), tick **Restrict to domain**, enter
`example.com`.

Only queries for that domain go to AdGuard; everything else resolves normally.
Adding it as a *global* nameserver instead gives ad blocking everywhere, at the
cost of making every device's DNS depend on the Pi being reachable.

### 4b. Subnet routing — needed for the domain to work remotely

AdGuard rewrites `example.com` to `192.168.1.10`, which is meaningless off the
LAN. Advertise the subnet so it becomes routable:

```
sudo tailscale up --advertise-routes=192.168.1.0/24 --advertise-tags=tag:server --accept-routes
```

Approve the route in the admin console under Machines → jigoku → route settings.

Forwarding must be enabled or this silently misbehaves:

```
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
```

### 5. ACL policy

Admin console → Access controls. The policy in
[`tailscale/policy.hujson`](../tailscale/policy.hujson) is the source of truth —
edit it here in git, then paste it in.

Key structure:

- `tag:server` — jigoku, enma. Full access between themselves.
- `tag:trusted` — your own devices. Full access.
- `tag:guest` — other people's devices. **Jellyfin only.**

### 5b. Sharing with people outside the tailnet

The mobile apps have **no auth-key sign-in option** — auth keys are a
headless/CLI mechanism only. For a family member, use node sharing instead:

Admin console → Machines → jigoku → `⋯` → **Share**. Send them the link; they
create a free Tailscale account and jigoku appears in *their* tailnet. They see
nothing else.

Shared users fall under `autogroup:shared`, **not** `tag:guest`, so the policy
needs a matching rule or they get no access at all:

```hujson
{
    "action": "accept",
    "src":    ["autogroup:shared"],
    "dst":    ["tag:server:8096", "tag:server:5055"],
},
```

### 6. Tag devices

```bash
# on jigoku
sudo tailscale up --advertise-tags=tag:server
```

For guests, generate a pre-authorised, tagged key rather than having them
authenticate as themselves:

Admin console → Settings → Keys → Generate auth key → **Pre-approved**,
**Ephemeral: no**, **Tags: tag:guest**.

Send them the key and the install link. Their device joins already restricted.

### 7. Onboard a guest

1. They install Tailscale (App Store / Microsoft Store)
2. They run `tailscale up --authkey=tskey-...`
3. They install Jellyfin or Swiftfin and point it at your domain
4. You create their Jellyfin account (doc 08)

## Verify

- [ ] `tailscale status` on jigoku lists all nodes
- [ ] From your phone on mobile data, `ping jigoku` resolves via MagicDNS
- [ ] The ACL tests pass (the admin console runs them when you save)
- [ ] From a `tag:guest` device: Jellyfin loads, SSH is refused
- [ ] Key expiry is disabled on both servers

## Rollback

```bash
sudo tailscale down
sudo tailscale logout
```

The ACL policy can be reverted in the admin console — it keeps a version
history, and you have the file in git regardless.

## Notes

### ACL tests are the safety net

The policy file supports assertions. They run every time you save, so a policy
that would break your own access is rejected before it applies:

```hujson
"tests": [
  { "src": "tag:guest", "accept": ["tag:server:8096"], "deny": ["tag:server:22"] },
]
```

This is the main reason ACLs are worth the effort rather than a flat tailnet —
the restriction is verified, not assumed.

### Why guests get tagged keys

If a guest authenticates with their own Tailscale account, the device belongs
to them and inherits their permissions, not your tags. A pre-authorised tagged
key means the device is tagged from the moment it joins and they can't change
it.

### If you get locked out

ACLs restrict device-to-device traffic. They do **not** restrict admin console
access, which is tied to your Tailscale login. So a bad policy is always
fixable from the web UI on any device.

### Subnet routing (optional)

enma can advertise your LAN subnet so remote devices reach LAN-only things
without Tailscale on each one:

```bash
sudo tailscale up --advertise-routes=192.168.1.0/24
```

Approve the route in the admin console. Not needed for this build — the TV is
the only Tailscale-less device and it never needs remote access.
