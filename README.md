# MindRoom LXC NixOS

<picture>
  <source media="(prefers-reduced-motion: no-preference)" srcset="https://raw.githubusercontent.com/mindroom-ai/mindroom/main/assets/logo/logo-mark-animated.svg" />
  <img src="https://raw.githubusercontent.com/mindroom-ai/mindroom/main/assets/logo/logo-mark.svg" alt="MindRoom Logo" align="right" width="120" />
</picture>

Standalone NixOS flake that runs the full MindRoom stack (local Matrix homeserver, MindRoom Chat web UI, Caddy, and MindRoom AI agents) inside an Incus LXC container.

Looking for a QEMU microVM instead? See [mindroom-ai/microvm-nixos](https://github.com/mindroom-ai/microvm-nixos).

## Deploy

Follow [AGENTS.md](AGENTS.md) for the exact copy-paste commands:

1. Clone this repo on an Incus host, launch a NixOS container, and mount the repo at `/mnt/repo`.
2. Add your SSH public key to [hosts/mindroom/default.nix](hosts/mindroom/default.nix).
3. Add your key and the container's SSH host key to `secrets.nix`, then run `./scripts/bootstrap-secrets.sh` with your LLM API key.
4. Run `nixos-rebuild switch --flake 'path:/mnt/repo#mindroom' --option sandbox false` inside the container.
5. Register your Matrix user and message `@mindroom_mind`.

## What runs

| Service | Role | Port |
| --- | --- | --- |
| `tuwunel` | Local Matrix homeserver | `127.0.0.1:8008` |
| `caddy` | HTTP reverse proxy | `80` |
| `mindroom-cinny` | MindRoom Chat web UI (built in-container) | `8090` (proxied by Caddy) |
| `mindroom-lab` | MindRoom agents on local Tuwunel (default on) | `127.0.0.1:8765` |
| `mindroom-chat` | MindRoom agents on hosted `mindroom.chat` (default off) | `127.0.0.1:8766` |
| `git-checkout-*` | Keeps MindRoom and MindRoom Chat at pinned commits | — |

The container runs with `security.nesting=true` and ships Docker, Incus, distrobox, and CLI dev tools. Toggle `lab` or `chat` in [hosts/mindroom/default.nix](hosts/mindroom/default.nix) (`chat` needs hosted `mindroom.chat` pairing credentials in `chat-runtime.env.age`). Changing domains in [hosts/mindroom/constants.nix](hosts/mindroom/constants.nix) also requires updating `MATRIX_SERVER_NAME` and `MINDROOM_OWNER_USER_ID` in `lab-runtime.env.age` and a matching MindRoom Chat build.

## Who has root

**Agents have full root inside the container by design.**
The MindRoom runtime runs as the `mindroom` operator account with passwordless `sudo`, Docker, and Incus access, and `/run/wrappers/bin` on its `PATH` so the agent's shell tool can run `sudo` directly.
Treat the container as the security boundary and as expendable; keep anything agents must not touch outside it.

## Your setup is in git

On first boot, `mindroom-lab` runs `mindroom config init --no-input --matrix-server self-hosted --provider openai` (reading `MINDROOM_OWNER_USER_ID` from `lab-runtime.env.age`), turns `/var/lib/mindroom/lab` into a Git repository, and commits the generated `config.yaml` and agent workspace.
A deny-by-default `.gitignore` tracks only `config.yaml`, `.gitignore`, and agent workspaces (excluding `.ssh/`, `.config/`, credentials, keys, `.env*`, venvs, caches, databases, and runtime state); agenix provides the runtime env; config init's starter `.env` is removed.
The agent's workspace `AGENTS.md` instructs it to stage only the files it changed, commit every setup change with a clear message, and never commit secrets.
The NixOS deployment flake belongs to the operator on the host.

## Security

- **TLS proxy required:** Caddy serves plain HTTP on port 80 only, while Matrix `.well-known` advertises `https://`. Put a TLS-terminating reverse proxy in front before exposing port 80 (or drop `:80` in [hosts/mindroom/caddy.nix](hosts/mindroom/caddy.nix) and open 443 in [hosts/mindroom/networking.nix](hosts/mindroom/networking.nix) to let Caddy terminate TLS on 80/443).
- **Firewall:** Only TCP 80, TCP 22, and mosh UDP 60000–61000 are open; Tuwunel and the runtime APIs listen on loopback only.
- **Secrets:** Committed `.age` files and `secrets.nix` are placeholders only; real secrets are encrypted with `ragenix` and decrypted at activation via `agenix`.

## Updates

Tuwunel, MindRoom, and MindRoom Chat versions are pinned in [hosts/mindroom/constants.nix](hosts/mindroom/constants.nix) and bumped daily by CI (or locally via `./scripts/update-pins.sh`).
To update, run `git pull` and re-run `nixos-rebuild switch --flake 'path:/mnt/repo#mindroom' --option sandbox false` (see [AGENTS.md](AGENTS.md#updating)). Clean checkouts advance to the new pins; checkouts with local changes are left untouched.

## Layout

- `AGENTS.md` — full step-by-step deployment runbook
- `flake.nix` — NixOS system, `ragenix` CLI, and eval check
- `hosts/mindroom/` — pins/domains (`constants.nix`), SSH keys & runtime toggles (`default.nix`), service configs
- `modules/` — Incus LXC glue (`lxc-container.nix`), base system, checkouts, agent runtimes, secrets
- `secrets/` + `hosts/mindroom/secrets/` — encrypted secrets and recipient lists (placeholders only)
- `templates/` + `scripts/` — secret templates, `bootstrap-secrets.sh`, `update-pins.sh`
