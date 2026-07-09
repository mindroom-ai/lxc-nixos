# Deployment Runbook

This file is the canonical, machine-followable path for deploying the `mindroom` NixOS configuration into a fresh Incus container.
Follow the steps in order; each step lists the exact command and what success looks like.

For background on what the deployed system contains, read [README.md](README.md).

## Preconditions

- A Linux host that runs (or can run) Incus.
  The Incus daemon is Linux-only.
- Shell access to that host.
- An SSH public key for the operator.
- `nix` available somewhere for secret bootstrapping: the Incus host, a workstation, or the container itself.

## 1. Install Incus on the Host (skip if present)

Ubuntu 24.04+: `sudo apt install incus`
Fedora: `sudo dnf install incus`
Ubuntu 22.04: use the Zabbly repository linked from <https://linuxcontainers.org/incus/docs/main/installing/>.

Then, once per host:

```bash
sudo usermod -aG incus-admin "$USER"
newgrp incus-admin
incus admin init --minimal
```

## 2. Clone This Repo on the Incus Host

```bash
git clone https://github.com/mindroom-ai/lxc-nixos.git
cd lxc-nixos
```

## 3. Launch the Container and Mount the Repo

```bash
incus launch images:nixos/unstable mindroom -c security.nesting=true
incus config device add mindroom repo disk source="$PWD" path=/mnt/repo shift=true
```

`security.nesting=true` is required for Docker/Incus inside the container.
`shift=true` maps host-side file ownership into the container's user namespace; without it the mounted repo is unreadable from inside.

## 4. Configure the Host Definition

Edit [hosts/mindroom/default.nix](hosts/mindroom/default.nix):

1. Put the operator SSH public key in `mindroom.runtime.authorizedKeys`.
   Without it the build succeeds but you get no SSH access.
2. Pick which agent runtimes to run (see README for what they are):
   - `lab.enable = true` (default): self-contained, talks to the local Tuwunel homeserver inside this container.
   - `chat.enable = false` (default): only enable if you have pairing credentials for the hosted mindroom.chat service.
     If you enable it, remember `--with-chat` in step 7.

## 5. Collect the Container Host SSH Key

```bash
incus exec mindroom -- /run/current-system/sw/bin/cat /etc/ssh/ssh_host_ed25519_key.pub
```

The stock NixOS image ships this key; the container uses it to decrypt secrets at activation time.

## 6. Configure Secret Recipients

Add BOTH the operator public key and the container host key from step 5 to the recipient lists in these two files:

- [secrets/shared/secrets.nix](secrets/shared/secrets.nix)
- [hosts/mindroom/secrets/secrets.nix](hosts/mindroom/secrets/secrets.nix)

The repo ships empty recipient arrays and placeholder `.age` files; the bootstrap script refuses to run until recipients are configured.

## 7. Bootstrap the Secrets

Run from the repo root, on any machine with Nix (`.#ragenix` uses the repo-pinned ragenix, which avoids version mismatches).

**Non-interactive (recommended for agents and automation):**

```bash
nix shell .#ragenix -c ./scripts/bootstrap-secrets.sh --non-interactive
```

No editor is opened: every secret is encrypted from its template, the Tuwunel registration token is auto-generated and written to BOTH `registration-token.age` and `lab-runtime.env.age`, and existing secrets are kept, so re-runs are safe.
This alone produces a fully working lab deployment; agents just cannot answer until a real LLM provider key exists.

To inject real values (API keys and the like), put files in a directory and pass `--values-dir`:

```bash
install -d -m 700 /dev/shm/mindroom-secrets
cat > /dev/shm/mindroom-secrets/agent-integrations.env <<'EOF'
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=...
EOF
nix shell .#ragenix -c ./scripts/bootstrap-secrets.sh --non-interactive --values-dir /dev/shm/mindroom-secrets
rm -rf /dev/shm/mindroom-secrets
```

File names in that directory (no `.age` suffix): `agent-integrations.env`, `agent-tooling.env`, `agent-runtime.env`, `lab-runtime.env`, `chat-runtime.env`, `registration-token`.
Missing files fall back to the template.
The directory holds plaintext secrets — keep it on tmpfs and delete it afterwards.

**Interactive (humans):**

```bash
nix shell .#ragenix -c ./scripts/bootstrap-secrets.sh
```

The script opens `$EDITOR` once per secret, pre-filled from the matching template (with the registration token already generated and synced into the lab env buffer).

Files created:

| Secret | Content |
| --- | --- |
| `secrets/shared/agent-integrations.env.age` | LLM provider API keys shared by all runtimes |
| `secrets/shared/agent-tooling.env.age` | tool credentials (GitHub, search, ...) |
| `hosts/mindroom/secrets/agent-runtime.env.age` | host-local settings shared by all runtimes |
| `hosts/mindroom/secrets/lab-runtime.env.age` | lab runtime env (template is pre-filled with working local values) |
| `hosts/mindroom/secrets/registration-token.age` | Tuwunel registration token — the file must contain ONLY the bare token |

Rules that matter:

- `registration-token.age` and the `MATRIX_REGISTRATION_TOKEN` value inside `lab-runtime.env.age` must be the SAME token.
  The bootstrap script keeps them in sync automatically; only if you edit these secrets by hand do you need to keep them identical yourself.
- The lab template's `MATRIX_HOMESERVER=http://127.0.0.1:8008` and `MATRIX_SERVER_NAME=mindroom.lab.mindroom.chat` defaults are correct for an unmodified deployment; keep them.
- Only bootstrap `chat-runtime.env.age` when you enabled the chat runtime: `./scripts/bootstrap-secrets.sh --with-chat`.
- Re-editing an existing secret interactively requires the operator private key.
  ragenix finds keys in the default SSH paths; otherwise pass `--identity /path/to/key`.
  Non-interactive runs never re-encrypt existing secrets.
- On a truly fresh clone every `.age` file is a `PLACEHOLDER_RAGENIX_SECRET` sentinel that the script replaces.
  If a previous attempt left real `.age` files behind (for example, encrypted before the host key was added to the recipients), a non-interactive run detects that they do not match the current recipients and fails with instructions; delete the listed files and re-run.

## 8. Preflight Checks

```bash
nix eval --raw .#nixosConfigurations.mindroom.config.system.build.toplevel.drvPath
incus exec mindroom -- /run/current-system/sw/bin/curl -sI https://github.com -o /dev/null -w '%{http_code}\n'
```

Expect a `/nix/store/...drv` path (plus a warning if you skipped the SSH key in step 4 — go back if so) and `200`.
A `warning: Git tree ... is dirty` message is expected — steps 4 and 6 edit the clone.
The checkout services clone from public GitHub at activation time, so GitHub must be reachable from the container.

## 9. Deploy

```bash
incus exec mindroom -- /run/current-system/sw/bin/nixos-rebuild switch \
  --flake 'path:/mnt/repo#mindroom' \
  --option sandbox false
```

- `#mindroom` selects `nixosConfigurations.mindroom` in `flake.nix` — it is NOT the container name; keep it as-is even if you named your container something else.
- Use `path:/mnt/repo#mindroom`, NOT `/mnt/repo#mindroom`: the `path:` prefix avoids Git ownership checks on the Incus-mounted filesystem.
- Keep `--option sandbox false` on the stock NixOS Incus image.
- The first switch downloads several GB; expect 10-30 minutes depending on bandwidth.
- If the switch ends with `warning: the following units failed` and a non-zero exit, do not immediately treat that as fatal: first-activation ordering races (checkouts and builds still running) self-heal via automatic restarts.
  Wait a minute, then run the checks below; only debug units that stay failed.

## 10. Post-Deploy Verification

The Cinny web UI is built inside the container on first activation, so `mindroom-cinny` takes a few extra minutes to come up after the switch finishes.
Check the build first:

```bash
incus exec mindroom -- /run/current-system/sw/bin/systemctl status mindroom-cinny-build --no-pager
```

Then the full set (drop `mindroom-lab` or add `mindroom-chat` to match your toggles):

```bash
incus exec mindroom -- /run/current-system/sw/bin/systemctl --failed --no-pager
incus exec mindroom -- /run/current-system/sw/bin/systemctl status \
  tuwunel caddy mindroom-lab mindroom-cinny --no-pager
```

Functional checks from the Incus host (replace the IP with the container's):

```bash
# Grab the eth0 address (the container also has a docker0 interface):
IP=$(incus list mindroom -c 4 -f csv | tr ',' '\n' | grep '(eth0)' | awk '{print $1}')
curl -s -H 'Host: mindroom.lab.mindroom.chat' "http://$IP/_matrix/client/versions" | head -c 200
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: chat.lab.mindroom.chat' "http://$IP/"
```

Expect Matrix version JSON and a `200`.

Logs when something is off:

```bash
incus exec mindroom -- /run/current-system/sw/bin/journalctl -u mindroom-lab -n 100 --no-pager
incus exec mindroom -- /run/current-system/sw/bin/journalctl -u mindroom-cinny-build -n 100 --no-pager
incus exec mindroom -- /run/current-system/sw/bin/journalctl -u tuwunel -n 100 --no-pager
```

## Expectations After Deploy

- `tuwunel`, `caddy`, and the Cinny web UI work with no external services.
- `mindroom-lab` registers its agents on the local homeserver using the registration token; agents need at least one real LLM provider key in `agent-integrations.env.age` to answer.
- `mindroom-lab` logs startup warnings about `__MINDROOM_OWNER_USER_ID_FROM_PAIRING__`; that placeholder is only filled by the hosted pairing flow and is harmless in lab mode.
- TLS: nothing in this container terminates TLS.
  Put a TLS-terminating reverse proxy in front (see README), or edit `hosts/mindroom/caddy.nix`.

## Recovery

If a checkout or build service fails transiently (network, OOM), rerun it:

```bash
incus exec mindroom -- /run/current-system/sw/bin/systemctl restart \
  git-checkout-cinny.service mindroom-cinny-build.service mindroom-cinny.service
```
