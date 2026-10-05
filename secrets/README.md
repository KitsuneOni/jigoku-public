# secrets/

Only SOPS-encrypted files (`*.enc.yaml`) belong here. Plaintext is gitignored.

## Setup

```
age-keygen -o ~/.config/sops/age/keys.txt
grep 'public key' ~/.config/sops/age/keys.txt
```

Put the **public** key in `.sops.yaml` at the repo root.
Put the **private** key in your password manager.

## Usage

```
sops secrets/jigoku.enc.yaml      # edit (encrypts on save)
sops -d secrets/jigoku.enc.yaml   # decrypt to stdout
```

## Expected files

| File | Contents |
|---|---|
| `jigoku.enc.yaml` | Cloudflare token, VPN key, Usenet creds, restic password, B2 keys |
| `homepage.enc.yaml` | Service API keys for dashboard widgets |

## Two things that are NOT in this repo and cannot be

1. **The age private key** — decrypts everything here
2. **The restic password** — losing it makes every backup permanently unrecoverable

Both live in your password manager. Nowhere else.

> **Public copy:** the encrypted `*.enc.yaml` files are intentionally not
> published here. Create your own with `sops secrets/jigoku.enc.yaml` after
> putting your age public key in `.sops.yaml`.
