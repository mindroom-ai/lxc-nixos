# Deployment Runbook

This file is the canonical, machine-followable path for deploying MindRoom as either a fresh Incus LXC container (`#mindroom`, steps 1–10 below) or a standalone QEMU microVM (`#mindroom-microvm`, see [MicroVM Deployment](#microvm-deployment)).
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
incus info mindroom >/dev/null 2>&1 && {
  echo "Container 'mindroom' already exists; refusing to continue."
  exit 1
}

incus launch images:nixos/unstable mindroom -c security.nesting=true
incus config device add mindroom repo disk source="$PWD" path=/mnt/repo shift=true
```

The guard must print nothing and continue only when `mindroom` does not exist.
If it prints the refusal message, stop: this runbook is for a fresh container, not an existing deployment.
`security.nesting=true` is required for Docker/Incus inside the container.
`shift=true` maps host-side file ownership into the container's user namespace; without it the mounted repo is unreadable from inside.
You may name the container something other than `mindroom`; if you do, substitute your name in every `incus` command below (but never in the flake attribute `#mindroom`, see step 9).

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
On a stock Nix install without flakes enabled in `nix.conf`, run `export NIX_CONFIG='extra-experimental-features = nix-command flakes'` first (a flag on the outer `nix shell` does not reach the inner `nix eval` calls in `scripts/bootstrap-secrets.sh`).
If you run this on a machine other than the Incus host, copy the results back into the clone mounted at `/mnt/repo` before deploying: the generated `.age` files AND both edited `secrets.nix` files.

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

The MindRoom Chat web UI is built inside the container on first activation, so `mindroom-cinny` takes a few extra minutes to come up after the switch finishes.
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

- `tuwunel`, `caddy`, and the MindRoom Chat web UI work with no external services.
- On the site domain only `/_matrix/*` and the well-known endpoints exist; other paths return 404 unless the chat runtime (which serves the app backend) is enabled.
- `mindroom-lab` registers its agents on the local homeserver using the registration token; agents need at least one real LLM provider key in `agent-integrations.env.age` to answer.
- `mindroom-lab` logs startup warnings about `__MINDROOM_OWNER_USER_ID_FROM_PAIRING__`; that placeholder is only filled by the hosted pairing flow.
  To register a local user and chat with `@mindroom_mind` in lab mode, run inside the guest (over SSH or `incus exec mindroom -- /run/wrappers/bin/sudo -iu mindroom bash`):

  ```bash
  USER_LOCALPART="you"
  PASSWORD=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
  TOKEN=$(sudo cat /run/agenix/registration-token)
  SESSION=$(curl -sS -X POST http://127.0.0.1:8008/_matrix/client/v3/register \
    -H 'Content-Type: application/json' \
    -d "$(jq -cn --arg u "$USER_LOCALPART" --arg p "$PASSWORD" '{username:$u,password:$p}')" | jq -r .session)
  USER_ID=$(jq -cn --arg u "$USER_LOCALPART" --arg p "$PASSWORD" --arg s "$SESSION" --arg t "$TOKEN" \
    '{username:$u,password:$p,auth:{type:"m.login.registration_token",token:$t,session:$s}}' | \
    curl -sS -X POST http://127.0.0.1:8008/_matrix/client/v3/register -H 'Content-Type: application/json' -d @- | \
    jq -r '.user_id // empty')
  unset TOKEN
  EXPECTED_ID="@${USER_LOCALPART}:mindroom.lab.mindroom.chat"
  if [ "$USER_ID" != "$EXPECTED_ID" ]; then
    echo "Registration failed (got '${USER_ID:-<empty>}')" >&2
    exit 1
  fi
  printf 'Registered %s with password: %s\n' "$USER_ID" "$PASSWORD"
  unset PASSWORD
  sed -i "s|__MINDROOM_OWNER_USER_ID_FROM_PAIRING__|\"$USER_ID\"|g" /var/lib/mindroom/lab/config.yaml
  sudo systemctl restart mindroom-lab
  ```

  YAML requires quotes around a leading `@`.
  After restart, `mindroom-lab` invites `$EXPECTED_ID` to the `personal` room.
- TLS: nothing in this container terminates TLS.
  Put a TLS-terminating reverse proxy in front (see README), or edit `hosts/mindroom/caddy.nix`.

## Updating

The deployed versions are pinned in [hosts/mindroom/constants.nix](hosts/mindroom/constants.nix): the Tuwunel release and the MindRoom/MindRoom Chat commits.
The `update-pins` GitHub workflow bumps the pins to the latest upstream daily (gated on `nix flake check`); `./scripts/update-pins.sh` does the same locally.

To apply updates to a running container: update the repo clone (`git pull`), then re-run the deploy command from step 9.
The switch moves the checkouts to the new pins and restarts the affected services; a MindRoom Chat pin bump rebuilds the web UI during the switch, which takes a few extra minutes.
Checkouts with local (uncommitted) changes are never touched by updates.

Upgrade notes for existing deployments:

- Existing `lab-runtime.env.age` / `chat-runtime.env.age` secrets created from older templates still contain empty `OPENAI_API_KEY=` (etc.) lines that overwrite values from `agent-integrations.env.age`; re-edit them with `ragenix` to remove or comment out unused overrides.
- A MindRoom Chat checkout (`/var/www/cinny`) with local edits stays at its old commit (the earlier Cinny-based `dev` client with root `serve.py`), so commit or discard those edits before switching.

## Recovery

If a checkout or build service fails transiently (network, OOM), rerun it:

```bash
incus exec mindroom -- /run/current-system/sw/bin/systemctl restart \
  git-checkout-cinny.service mindroom-cinny-build.service mindroom-cinny.service
```

## MicroVM Deployment

Run the same MindRoom stack directly on a Linux host as a standalone QEMU microVM via `microvm.nix` — no Incus required.

### Preconditions

- An `x86_64-linux` host with `/dev/kvm` readable and writable by your user (`[ -r /dev/kvm ] && [ -w /dev/kvm ]`; otherwise QEMU silently falls back to software TCG emulation).
- `ssh-keygen` and `nix` (on stock Nix without flakes in `nix.conf`, run `export NIX_CONFIG='extra-experimental-features = nix-command flakes'` first).
- At least 8 GiB free RAM (for the first-boot MindRoom Chat build and `uv` installs) and an operator SSH public key.
- **Host isolation note:** QEMU user (SLIRP) networking allows the guest to reach host `127.0.0.1` loopback services via `10.0.2.2`, and the 9p `ro-store` share exposes the entire host `/nix/store`.
  Run this default configuration only on a host without sensitive loopback-only services or secrets in `/nix/store` (for stronger isolation, switch to `microvm.storeOnDisk = true` and `tap` networking in [modules/microvm-guest.nix](modules/microvm-guest.nix)).

### M1. Clone and Configure the Host

Follow steps 2 and 4 above (`git clone`, add your SSH public key in `hosts/mindroom/default.nix`) and note the repo's absolute path (`REPO=$PWD`).
The VM forwards host loopback `127.0.0.1:8080 -> 80` (Caddy) and `127.0.0.1:2222 -> 22` (SSH); if either host port is already in use, edit `microvm.forwardPorts` in [modules/microvm-guest.nix](modules/microvm-guest.nix).

### M2. Generate the Guest SSH Host Key in a Private State Dir (Before First Boot)

Keep VM state **outside** any git work tree (a `path:` flake ref copies untracked files inside a repo into the world-readable `/nix/store`):

```bash
STATE_DIR=~/.local/state/mindroom-microvm
install -d -m 700 "$STATE_DIR"
if [ "$(git -C "$STATE_DIR" rev-parse --is-inside-work-tree 2>/dev/null || true)" = "true" ]; then
  echo "Refusing to place VM state inside a git work tree: $STATE_DIR" >&2
  exit 1
fi
install -d -m 700 "$STATE_DIR/ssh"
ssh-keygen -q -t ed25519 -N "" -C "root@mindroom" -f "$STATE_DIR/ssh/ssh_host_ed25519_key"
cat "$STATE_DIR/ssh/ssh_host_ed25519_key.pub"
```

The runner mounts `$STATE_DIR/ssh` read-only early in boot (`neededForBoot = true`), so `agenix` decrypts secrets on first boot and `sshd` keeps a stable host identity across reboots.

### M3. Configure Recipients and Bootstrap Secrets

From the repo root (`$REPO`), follow steps 6 and 7 above, using the `$STATE_DIR/ssh/ssh_host_ed25519_key.pub` line from step M2 as the host recipient.

### M4. Preflight Check

From the repo root (`$REPO`):

```bash
nix flake check
```

Expect `all checks passed!` (eval-only for both `#mindroom` and `#mindroom-microvm`).

### M5. Build and Start the MicroVM

Run from `$STATE_DIR` using the repo's absolute path.
Building with `--out-link runner` keeps a host Nix GC root for the store paths the guest runs over 9p; `microvm-run` enforces `0700` on `$STATE_DIR` and `umask 077`, creating `0600` sparse ext4 images `var.img`, `srv.img`, and `nix-store.img` plus `control.sock` there, and refuses to start inside a git work tree:

```bash
cd "$STATE_DIR"
nix build --out-link runner "$REPO#mindroom-microvm"
./runner/bin/microvm-run
```

The runner starts QEMU in the foreground with the serial console attached (run inside `tmux` or another terminal to detach).
SSH comes up in ~30–40 seconds; first-boot git checkouts, the MindRoom Chat web UI build, and `mindroom-lab` `uv` install take ~2 minutes on a fast connection.

### M6. Verify from the Host

From another terminal on the host (adjust `STATE_DIR` or `2222`/`8080` if you changed them):

```bash
STATE_DIR=~/.local/state/mindroom-microvm
install -d -m 700 ~/.ssh
line="[127.0.0.1]:2222 $(cat "$STATE_DIR/ssh/ssh_host_ed25519_key.pub")"
grep -qxF "$line" ~/.ssh/known_hosts 2>/dev/null || echo "$line" >> ~/.ssh/known_hosts

# Wait for SSH and all first-boot services (checkouts + UI build + mindroom-lab uv install)
timeout 600 bash -c 'until ssh -n -o BatchMode=yes -p 2222 mindroom@127.0.0.1 \
  "systemctl is-active -q tuwunel && systemctl is-active -q caddy && systemctl is-active -q mindroom-cinny && systemctl is-active -q mindroom-lab" 2>/dev/null \
  && curl -sf -H "Host: chat.lab.mindroom.chat" http://127.0.0.1:8080/ >/dev/null; do sleep 10; done'

ssh -o BatchMode=yes -p 2222 mindroom@127.0.0.1 'systemctl --failed --no-pager && systemctl is-active tuwunel caddy mindroom-cinny mindroom-lab'
curl -s -H 'Host: mindroom.lab.mindroom.chat' http://127.0.0.1:8080/_matrix/client/versions | head -c 200
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: chat.lab.mindroom.chat' http://127.0.0.1:8080/
```

Expect `0 loaded units listed.`, four `active` lines, Matrix version JSON, and `200`.

### Stopping, Rebooting, and Updating the MicroVM

Stop cleanly so the ext4 volumes unmount cleanly (set `STATE_DIR` in a new terminal):

```bash
STATE_DIR=~/.local/state/mindroom-microvm
cd "$STATE_DIR"
./runner/bin/microvm-shutdown
# Or via SSH:
ssh -o BatchMode=yes -p 2222 mindroom@127.0.0.1 'sudo poweroff'
```

Re-running `./runner/bin/microvm-run` from `$STATE_DIR` reuses `var.img`, `srv.img`, and `nix-store.img` (checkouts, built UI, Tuwunel DB, agent accounts, guest-installed Nix store paths, and multi-boot journals survive without rebuilding the UI).

To apply updates:

```bash
REPO=/abs/path/to/lxc-nixos
STATE_DIR=~/.local/state/mindroom-microvm
git -C "$REPO" pull
cd "$STATE_DIR"
./runner/bin/microvm-shutdown
nix build --out-link runner "$REPO#mindroom-microvm"
./runner/bin/microvm-run
```
