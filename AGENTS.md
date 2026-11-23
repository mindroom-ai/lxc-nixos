# Deployment Runbook

This file is the canonical, machine-followable path for deploying the `mindroom` NixOS configuration into a fresh Incus container.
Follow the steps in order; each step lists the exact command and what success looks like.

For a high-level overview, read [README.md](README.md); full technical, security, TLS, customization, and verification details are in [Reference](#reference) below.

## Preconditions

- A Linux host that runs (or can run) Incus.
  The Incus daemon is Linux-only.
- Shell access to that host.
- An SSH public key for the operator.
- `nix` on a Linux machine for secret bootstrapping (the Incus host, a Linux workstation, or the container itself); the bootstrap script stages plaintext only on tmpfs, which macOS lacks.

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
2. Pick which agent runtimes to run (see [Runtimes and Secrets](#runtimes-and-secrets)):
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
The `nix shell` command needs flakes enabled; on a stock Nix install add `--extra-experimental-features 'nix-command flakes'` after `nix`.
If you run this on a machine other than the Incus host, copy the results back into the clone mounted at `/mnt/repo` before deploying: the generated `.age` files AND both edited `secrets.nix` files.

**Non-interactive (recommended for agents and automation):**

If `OPENAI_API_KEY` is already exported in your environment, it is used directly; otherwise `read -rsp` prompts silently on a TTY (or fails closed if stdin is not a TTY) so the key never enters shell history.
Plaintext staging requires a filesystem verified as `tmpfs` (`$XDG_RUNTIME_DIR` then `/dev/shm`, failing closed otherwise) and is deleted on subshell exit:

```bash
(
  set -euo pipefail
  if [ -z "${OPENAI_API_KEY:-}" ]; then
    if [ ! -t 0 ]; then
      echo "OPENAI_API_KEY is not set and stdin is not a TTY; export OPENAI_API_KEY and re-run." >&2
      exit 1
    fi
    read -rsp "OPENAI_API_KEY: " OPENAI_API_KEY
    echo
  fi
  TMPFS_BASE=""
  for candidate in "${XDG_RUNTIME_DIR:-}" /dev/shm; do
    if [ -n "$candidate" ] && [ -d "$candidate" ] && [ -w "$candidate" ] \
      && [ "$(stat -f -c %T "$candidate" 2>/dev/null || true)" = "tmpfs" ]; then
      TMPFS_BASE="$candidate"
      break
    fi
  done
  [ -n "$TMPFS_BASE" ] || { echo "Neither \$XDG_RUNTIME_DIR nor /dev/shm is a writable tmpfs; refusing to stage plaintext secrets on disk." >&2; exit 1; }
  SECRETS_TMP="$(umask 077 && mktemp -d "$TMPFS_BASE/mindroom-secrets.XXXXXX")"
  trap 'rm -rf "$SECRETS_TMP"' EXIT
  (umask 077 && printf 'OPENAI_API_KEY=%s\n' "$OPENAI_API_KEY" > "$SECRETS_TMP/agent-integrations.env")
  nix shell .#ragenix -c ./scripts/bootstrap-secrets.sh --non-interactive --values-dir "$SECRETS_TMP"
)
```

Supported filenames in `--values-dir` (no `.age` suffix): `agent-integrations.env`, `agent-tooling.env`, `agent-runtime.env`, `lab-runtime.env`, `chat-runtime.env`, `registration-token`.
Missing files fall back to `templates/`.
If you enabled `chat.enable = true`, add a line inside the step-7 block before `nix shell …` to write `$SECRETS_TMP/chat-runtime.env`, and append `--with-chat`.

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
- `templates/lab-runtime.env.example` sets `MINDROOM_OWNER_USER_ID=@you:mindroom.lab.mindroom.chat`, which `mindroom config init` reads on first boot to populate `administrators` and `room_defaults` without editing `config.yaml` (change the localpart in `lab-runtime.env` before first boot if you want a different username). agenix provides the runtime env; config init's starter `.env` is removed.
- Only bootstrap `chat-runtime.env.age` when you enabled the chat runtime: `./scripts/bootstrap-secrets.sh --with-chat`.
- Upgrading an existing deployment:
  - Add `MINDROOM_OWNER_USER_ID=@you:mindroom.lab.mindroom.chat` (or your Matrix user ID) to `lab-runtime.env.age`, and replace `__MINDROOM_OWNER_USER_ID_FROM_PAIRING__` in `/var/lib/mindroom/lab/config.yaml` once with your YAML-quoted Matrix user ID (for example `"@you:mindroom.lab.mindroom.chat"`).
  - agenix values now win over any local `.env`; put overrides in the encrypted runtime env (`lab-runtime.env.age` / `chat-runtime.env.age`) and delete any empty lines such as `OPENAI_API_KEY=` that would override `agent-integrations.env.age`.
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

## 11. Register a Local Lab User and Verify an Agent Reply

On first boot, `mindroom-lab` runs `mindroom config init --no-input --matrix-server self-hosted --provider openai` (filling your owner ID from `MINDROOM_OWNER_USER_ID` in `lab-runtime.env.age`), registers its agents (`@mindroom_user`, `@mindroom_router`, `@mindroom_mind`) on local Tuwunel, and initializes `/var/lib/mindroom/lab` as a Git repository, with an initial commit on fresh deployments (an upgraded state dir is left unstaged for review).
Register the owner Matrix account, restart `mindroom-lab` so it invites you to the `personal` room, accept the invite, and verify a live reply from `@mindroom_mind` (requires a valid LLM provider key from step 7):

```bash
incus exec mindroom -- /run/current-system/sw/bin/su - mindroom -s /run/current-system/sw/bin/bash <<'EOF'
set -euo pipefail
strip_quotes() {
  local v="$1"
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "$v"
}
SERVER_NAME=$(strip_quotes "$(sudo awk -F= '$1=="MATRIX_SERVER_NAME"{sub(/^[^=]*=/,""); print; exit}' /run/agenix/lab-runtime-env | tr -d '\r')")
SERVER_NAME="${SERVER_NAME:-mindroom.lab.mindroom.chat}"
OWNER_ID=$(strip_quotes "$(sudo awk -F= '$1=="MINDROOM_OWNER_USER_ID"{sub(/^[^=]*=/,""); print; exit}' /run/agenix/lab-runtime-env | tr -d '\r')")
if [ -z "$OWNER_ID" ] || [ "$OWNER_ID" = "__MINDROOM_OWNER_USER_ID_FROM_PAIRING__" ]; then
  echo "MINDROOM_OWNER_USER_ID is unset or still a placeholder in /run/agenix/lab-runtime-env; set it to @<user>:$SERVER_NAME and re-deploy before registering." >&2
  exit 1
fi
if grep -qF "__MINDROOM_OWNER_USER_ID_FROM_PAIRING__" /var/lib/mindroom/lab/config.yaml; then
  echo "/var/lib/mindroom/lab/config.yaml still contains __MINDROOM_OWNER_USER_ID_FROM_PAIRING__; replace it with \"$OWNER_ID\" and restart mindroom-lab before registering." >&2
  exit 1
fi
case "$OWNER_ID" in
  @*:* ) ;;
  *)
    echo "Invalid MINDROOM_OWNER_USER_ID '$OWNER_ID' (expected @<user>:$SERVER_NAME)." >&2
    exit 1
    ;;
esac
OWNER_DOMAIN="${OWNER_ID#*:}"
if [ "$OWNER_DOMAIN" != "$SERVER_NAME" ]; then
  echo "MINDROOM_OWNER_USER_ID domain '$OWNER_DOMAIN' does not match MATRIX_SERVER_NAME '$SERVER_NAME'." >&2
  exit 1
fi
USER_LOCALPART="${OWNER_ID#@}"
USER_LOCALPART="${USER_LOCALPART%%:*}"
PASSWORD=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
TOKEN=$(sudo cat /run/agenix/registration-token)
SESSION=$(curl -sS -X POST http://127.0.0.1:8008/_matrix/client/v3/register \
  -H 'Content-Type: application/json' \
  -d "$(jq -cn --arg u "$USER_LOCALPART" --arg p "$PASSWORD" '{username:$u,password:$p}')" | jq -r .session)
REG=$(jq -cn --arg u "$USER_LOCALPART" --arg p "$PASSWORD" --arg s "$SESSION" --arg t "$TOKEN" \
  '{username:$u,password:$p,auth:{type:"m.login.registration_token",token:$t,session:$s}}' | \
  curl -sS -X POST http://127.0.0.1:8008/_matrix/client/v3/register -H 'Content-Type: application/json' -d @-)
unset TOKEN
USER_ID=$(printf '%s' "$REG" | jq -r '.user_id // empty')
ACCESS_TOKEN=$(printf '%s' "$REG" | jq -r '.access_token // empty')
if [ "$USER_ID" != "$OWNER_ID" ] || [ -z "$ACCESS_TOKEN" ]; then
  echo "Registration failed (got '${USER_ID:-<empty>}')" >&2
  exit 1
fi
(umask 077 && printf '%s\n' "$PASSWORD" > "$HOME/.lab-user-password")
unset PASSWORD
printf 'Registered %s (password saved in ~/.lab-user-password, mode 0600)\n' "$USER_ID"

# Restart mindroom-lab so it invites the newly registered owner to the personal room.
sudo systemctl restart mindroom-lab

# Wait for the invite to the personal room, join it, and send a test prompt.
ROOM_ID=""
for _ in $(seq 1 60); do
  ROOM_ID=$(curl -sS -H "Authorization: Bearer $ACCESS_TOKEN" \
    'http://127.0.0.1:8008/_matrix/client/v3/sync?timeout=2000' | \
    jq -r '
      ((.rooms.invite // {}) | to_entries | map(select(any(.value.invite_state.events[]?; .type == "m.room.name" and (.content.name // "" | ascii_downcase) == "personal"))) | .[0].key)
      // empty
    ')
  [ -n "$ROOM_ID" ] && break
  sleep 2
done
[ -n "$ROOM_ID" ] || { echo "Timed out waiting for personal room invite" >&2; exit 1; }

ENC_ROOM=$(jq -rn --arg r "$ROOM_ID" '$r|@uri')
curl -sfS -X POST -H "Authorization: Bearer $ACCESS_TOKEN" -H 'Content-Type: application/json' \
  -d '{}' "http://127.0.0.1:8008/_matrix/client/v3/join/$ENC_ROOM" >/dev/null
sleep 2
curl -sfS -X PUT -H "Authorization: Bearer $ACCESS_TOKEN" -H 'Content-Type: application/json' \
  -d '{"msgtype":"m.text","body":"@mindroom_mind reply with exactly: LXC-OK","m.mentions":{"user_ids":["@mindroom_mind:mindroom.lab.mindroom.chat"]}}' \
  "http://127.0.0.1:8008/_matrix/client/v3/rooms/$ENC_ROOM/send/m.room.message/test-$(date +%s)" >/dev/null

# Poll for @mindroom_mind's reply (handles both initial messages and streaming edits).
REPLY=""
for _ in $(seq 1 45); do
  REPLY=$(curl -sS -H "Authorization: Bearer $ACCESS_TOKEN" \
    "http://127.0.0.1:8008/_matrix/client/v3/rooms/$ENC_ROOM/messages?dir=b&limit=20" | \
    jq -r '.chunk[]
      | select(.type == "m.room.message" and .sender == "@mindroom_mind:mindroom.lab.mindroom.chat")
      | (.content."m.new_content".body // .content.body // "")
      | select(contains("LXC-OK"))' | head -n 1)
  [ -n "$REPLY" ] && break
  sleep 2
done
unset ACCESS_TOKEN
[ -n "$REPLY" ] || { echo "Timed out waiting for @mindroom_mind reply" >&2; exit 1; }
printf 'Reply from @mindroom_mind: %s\n' "$REPLY"
EOF
```

Expect `Registered @you:mindroom.lab.mindroom.chat ...` followed by `Reply from @mindroom_mind: LXC-OK`.

## Expectations After Deploy

- `tuwunel`, `caddy`, and the MindRoom Chat web UI work with no external services.
- On the site domain only `/_matrix/*` and the well-known endpoints exist; other paths return 404 unless the chat runtime (which serves the app backend) is enabled.
- `mindroom-lab` runs as `mindroom` with passwordless `sudo`, Docker, and Incus access, and keeps its setup (`/var/lib/mindroom/lab`) in Git.
- When signing in through MindRoom Chat (which defaults to hosted `mindroom.chat`), enter the lab homeserver `https://mindroom.lab.mindroom.chat` (served through your TLS proxy) before logging in.
- TLS: nothing in this container terminates TLS.
  Put a TLS-terminating reverse proxy in front (see [TLS Model](#tls-model)), or edit `hosts/mindroom/caddy.nix` and `hosts/mindroom/networking.nix`.

## Updating

The deployed versions are pinned in [hosts/mindroom/constants.nix](hosts/mindroom/constants.nix): the Tuwunel release and the MindRoom/MindRoom Chat commits.
The `update-pins` GitHub workflow bumps the pins to the latest upstream daily (gated on `nix flake check`); `./scripts/update-pins.sh` does the same locally.

To apply updates to a running container: update the repo clone (`git pull`), then re-run the deploy command from step 9.
The switch moves the checkouts to the new pins and restarts the affected services; a MindRoom Chat pin bump rebuilds the web UI during the switch, which takes a few extra minutes.
Checkouts with local (uncommitted) changes are never touched by updates.

## Recovery

If a checkout or build service fails transiently (network, OOM), rerun it:

```bash
incus exec mindroom -- /run/current-system/sw/bin/systemctl restart \
  git-checkout-cinny.service mindroom-cinny-build.service mindroom-cinny.service
```

## Reference

### Services and Ports

| Service | Purpose | Port |
| --- | --- | --- |
| `tuwunel` | Local Matrix homeserver (MindRoom Tuwunel fork, pinned release binary) | 8008 (loopback) |
| `caddy` | HTTP reverse proxy / routing for the public hostnames | 80 |
| `mindroom-cinny` | MindRoom Chat web client (built in-container on first activation) | 8090 (all interfaces; not open in the container firewall) |
| `mindroom-lab` | MindRoom agent runtime — local homeserver (optional, default on) | 8765 (loopback; unauthenticated dashboard/API, not proxied) |
| `mindroom-chat` | MindRoom agent runtime — hosted mindroom.chat (optional, default off) | 8766 (loopback; proxied by Caddy when enabled) |
| `git-checkout-*` | Keep the MindRoom and MindRoom Chat checkouts at the pinned revisions | — |

### Container Environment and Caveats

The container also ships Docker, Incus, distrobox, and a CLI/dev toolbox for the operator account and the agents.

Known caveats:

- The first activation clones two repos and builds the MindRoom Chat web UI inside the container; on slow networks the UI service can take several minutes after the switch returns.
  `systemctl --failed` plus the recovery commands in [Recovery](#recovery) cover the transient cases.
- `mindroom-lab` needs at least one real LLM provider key (in `agent-integrations.env.age`) before agents respond to messages.
- Nested virtualization (KVM/libvirt) is intentionally not enabled; a plain Incus container has no `/dev/kvm`.

### Runtimes and Secrets

MindRoom runs as up to two independent instances of the same application, toggled in [hosts/mindroom/default.nix](hosts/mindroom/default.nix):

- **lab** (`mindroom.runtime.lab.enable`, default `true`): agents that register and log in on the **local Tuwunel homeserver inside this container**, using the registration token you create during secret bootstrap.
  Fully self-contained — this is the one you want when trying the repo out.
- **chat** (`mindroom.runtime.chat.enable`, default `false`): agents that connect out to the **hosted mindroom.chat homeserver**.
  Requires pairing credentials (`MINDROOM_LOCAL_CLIENT_ID/SECRET`) in `chat-runtime.env.age`, so leave it off unless you have them.

Each enabled runtime gets its own state directory, `config.yaml` (generated on first boot by `mindroom config init --no-input --matrix-server <preset> --provider openai`, filling the owner from `MINDROOM_OWNER_USER_ID`), uv environment, and encrypted env file; they share the two org-wide secret bundles (`agent-integrations`, `agent-tooling`).
agenix provides the runtime env; `config init`'s starter `.env` is removed on fresh init without deleting any pre-existing operator `.env`.
On first boot, the state directory is also initialized as a Git repo with a deny-by-default `.gitignore` tracking only `config.yaml`, `.gitignore`, and agent workspaces (committing a freshly generated setup, while leaving upgraded state directories unstaged for review), and the agent's workspace `AGENTS.md` instructs it to commit every setup change in the owning repo without secrets.
Secrets are only required for runtimes you actually enable.
Encrypted secrets and their recipient lists live in `secrets/shared/` and `hosts/mindroom/secrets/` (the repo ships placeholders only), seeded from plaintext templates in `templates/`.

### Security Model

The container is the security boundary, and everything inside it is deliberately trusted:
the agents run as the operator account, which has passwordless sudo, Docker, and Incus access (with `/run/wrappers/bin` on `PATH` so the agent shell tool can run `sudo` directly), so **agents have full root inside the container by design**.
Because the deployment repo is mounted writable at `/mnt/repo`, guest root (including agents) can also modify files in that host checkout.
Treat the container as expendable, and do not put anything inside it that the agents must not touch.
The container firewall opens TCP 80 (Caddy), TCP 22 (SSH), and UDP 60000–61000 (mosh); Tuwunel and the runtime APIs listen on loopback.

### TLS Model

Caddy binds **port 80 only**.
In the reference setup an external reverse proxy (Traefik) owns the certificates for the public `*.lab.mindroom.chat` hostnames and forwards plain HTTP to this container.
The well-known responses advertise `https://` URLs on that assumption.

If you have no TLS-terminating proxy in front, do not expose port 80 to the internet as-is.
Either put one there, or remove the `":80"` suffixes in [hosts/mindroom/caddy.nix](hosts/mindroom/caddy.nix) and open port 443 in [hosts/mindroom/networking.nix](hosts/mindroom/networking.nix) so Caddy provisions certificates itself (needs public DNS and reachability on 80/443).

### Version Pinning and Updates

Everything that runs is pinned in [hosts/mindroom/constants.nix](hosts/mindroom/constants.nix): the Tuwunel release (`tuwunelVersion` + hash) and the exact commits of the MindRoom and MindRoom Chat checkouts (`mindroomRev`, `cinnyRev`).
The [update-pins](.github/workflows/update-pins.yml) GitHub workflow bumps all three to the latest upstream daily and pushes only after `nix flake check` passes; run [scripts/update-pins.sh](scripts/update-pins.sh) to do the same by hand.
Applying an update to a running container is `git pull` in the repo clone plus the same `nixos-rebuild switch` used to deploy (see [Updating](#updating)) — the checkout services move to the new pins and the affected services restart (a MindRoom Chat pin bump rebuilds the web UI, which adds a few minutes to the switch).
A checkout with local changes is never touched, so in-container experiments survive switches; clean checkouts are reset to the pinned commit.

### Customization Points

- [hosts/mindroom/default.nix](hosts/mindroom/default.nix): runtime toggles, operator SSH keys, state paths
- [hosts/mindroom/constants.nix](hosts/mindroom/constants.nix): public domains, the Tuwunel release pin, and the MindRoom/MindRoom Chat commit pins
- [hosts/mindroom/mindroom.nix](hosts/mindroom/mindroom.nix), [hosts/mindroom/cinny.nix](hosts/mindroom/cinny.nix): which repos are checked out and which pins they follow

Changing the public domains in `constants.nix` is not enough by itself: `MATRIX_SERVER_NAME` and `MINDROOM_OWNER_USER_ID` inside `lab-runtime.env.age` must match, and MindRoom Chat bakes its homeserver defaults into its own build, so a full domain change also needs a matching client-side change.

### What Was Verified

Verified end-to-end on 2026-07-08 by deploying a fresh `images:nixos/unstable` Incus container from this repo, following the runbook above literally:

- `nix flake` evaluation and full toplevel build
- secret bootstrap via `nix shell .#ragenix -c ./scripts/bootstrap-secrets.sh` (including the refusal path when recipients are missing) and agenix decryption inside the container at activation
- `nixos-rebuild switch --flake 'path:/mnt/repo#mindroom'` from the host-mounted repo
- `tuwunel`, `caddy` up; Matrix client API answering through Caddy
- the in-container MindRoom Chat build (`mindroom-cinny-build`) and the web UI serving through Caddy
- `mindroom-lab` starting, installing its uv environment from the `/srv/mindroom` checkout, and registering agents on the local homeserver with the bootstrap registration token

Re-verified on 2026-11-23 in a fresh throwaway Incus container: the step-11 test user got a live agent reply with a real OpenAI key; the agent ran `sudo -n id -u` (`0`), edited its own workspace and committed it to `/var/lib/mindroom/lab`; history survived `incus restart`.

Not verified: the `chat` runtime against the hosted mindroom.chat service (needs real pairing credentials), and running with a TLS-terminating proxy in front.
