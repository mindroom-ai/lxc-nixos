# MindRoom LXC NixOS

Standalone NixOS flake for running the MindRoom stack in an Incus LXC container: local Matrix homeserver, web clients, and the MindRoom AI agent runtime, with all secrets managed through `ragenix`.

**To deploy, follow [AGENTS.md](AGENTS.md)** — it is the canonical step-by-step runbook, written to be followed verbatim by a human or an agent.
This README explains what you get and which knobs exist.

## What Runs Inside the Container

| Service | Purpose | Port |
| --- | --- | --- |
| `tuwunel` | Local Matrix homeserver (MindRoom Tuwunel fork, pinned release binary) | 8008 (loopback) |
| `caddy` | HTTP reverse proxy / routing for the public hostnames | 80 |
| `mindroom-cinny` | Cinny web client fork (built in-container on first activation) | 8090 (all interfaces; the firewall only opens 80) |
| `mindroom-lab` | MindRoom agent runtime — local homeserver (optional, default on) | 8765 (loopback; unauthenticated dashboard/API, not proxied) |
| `mindroom-chat` | MindRoom agent runtime — hosted mindroom.chat (optional, default off) | 8766 (loopback; proxied by Caddy when enabled) |
| `git-checkout-*` | Keep the mindroom/cinny checkouts at the pinned revisions | — |

The container also ships Docker, Incus, distrobox, and a CLI/dev toolbox for the operator account and the agents.

## One Application, Two Runtimes

MindRoom runs as up to two independent instances of the same application, toggled in [hosts/mindroom/default.nix](hosts/mindroom/default.nix):

- **lab** (`mindroom.runtime.lab.enable`, default `true`): agents that register and log in on the **local Tuwunel homeserver inside this container**, using the registration token you create during secret bootstrap.
  Fully self-contained — this is the one you want when trying the repo out.
- **chat** (`mindroom.runtime.chat.enable`, default `false`): agents that connect out to the **hosted mindroom.chat homeserver**.
  Requires pairing credentials (`MINDROOM_LOCAL_CLIENT_ID/SECRET`) in `chat-runtime.env.age`, so leave it off unless you have them.

Each enabled runtime gets its own state directory, `config.yaml`, uv environment, and encrypted env file; they share the two org-wide secret bundles (`agent-integrations`, `agent-tooling`).
Secrets are only required for runtimes you actually enable.

## Security Model

The container is the security boundary, and everything inside it is deliberately trusted:
the agents run as the operator account, which has passwordless sudo and Docker access, so **agents have root inside the container by design**.
Treat the container as expendable, and do not put anything inside it that the agents must not touch.
Externally, only port 80 is open; Tuwunel and the runtime APIs listen on loopback.

## Version Pinning and Updates

Everything that runs is pinned in [hosts/mindroom/constants.nix](hosts/mindroom/constants.nix): the Tuwunel release (`tuwunelVersion` + hash) and the exact commits of the mindroom and cinny checkouts (`mindroomRev`, `cinnyRev`).
The `update-pins` GitHub workflow bumps all three to the latest upstream daily and pushes only after `nix flake check` passes; run [scripts/update-pins.sh](scripts/update-pins.sh) to do the same by hand.
Applying an update to a running container is `git pull` in the repo clone plus the same `nixos-rebuild switch` used to deploy — the checkout services move to the new pins and the affected services restart (a cinny bump rebuilds the web UI, which adds a few minutes to the switch).
A checkout with local changes is never touched, so in-container experiments survive switches; clean checkouts are reset to the pinned commit.

## TLS Model (Read This Before Exposing Anything)

Caddy binds **port 80 only**.
In the reference setup an external reverse proxy (Traefik) owns the certificates for the public `*.lab.mindroom.chat` hostnames and forwards plain HTTP to this container.
The well-known responses advertise `https://` URLs on that assumption.

If you have no TLS-terminating proxy in front, do not expose port 80 to the internet as-is.
Either put one there, or remove the `":80"` suffixes in [hosts/mindroom/caddy.nix](hosts/mindroom/caddy.nix) so Caddy provisions certificates itself (needs public DNS and reachability on 80/443).

## Repository Layout

- `hosts/mindroom/` — host composition: domains/pins (`constants.nix`), runtime toggles and SSH keys (`default.nix`), per-service config
- `modules/` — reusable modules (base system, LXC glue, git checkouts, runtime services, secrets wiring)
- `secrets/shared/` + `hosts/mindroom/secrets/` — encrypted secrets and their recipient lists (the repo ships placeholders only)
- `templates/` — plaintext templates that seed each secret during bootstrap
- `scripts/bootstrap-secrets.sh` — guided secret creation
- `AGENTS.md` — the deployment runbook

## Customization Points

- [hosts/mindroom/default.nix](hosts/mindroom/default.nix): runtime toggles, operator SSH keys, state paths
- [hosts/mindroom/constants.nix](hosts/mindroom/constants.nix): public domains, the Tuwunel release pin, and the mindroom/cinny commit pins
- [hosts/mindroom/mindroom.nix](hosts/mindroom/mindroom.nix), [cinny.nix](hosts/mindroom/cinny.nix): which repos are checked out and which pins they follow

Changing the public domains in `constants.nix` is not enough by itself: `MATRIX_SERVER_NAME` inside `lab-runtime.env.age` must match, and the Cinny fork bakes its homeserver defaults into its own build, so a full domain change also needs a matching cinny-side change.

## What Was Verified

Verified end-to-end on 2026-07-08 by deploying a fresh `images:nixos/unstable` Incus container from this repo, following AGENTS.md literally:

- `nix flake` evaluation and full toplevel build
- secret bootstrap via `nix shell .#ragenix -c ./scripts/bootstrap-secrets.sh` (including the refusal path when recipients are missing) and agenix decryption inside the container at activation
- `nixos-rebuild switch --flake 'path:/mnt/repo#mindroom'` from the host-mounted repo
- `tuwunel`, `caddy` up; Matrix client API answering through Caddy
- the in-container Cinny build (`mindroom-cinny-build`) and the web UI serving through Caddy
- `mindroom-lab` starting, installing its uv environment from the `/srv/mindroom` checkout, and registering agents on the local homeserver with the bootstrap registration token

Not verified: agent conversations with real LLM provider keys, the `chat` runtime against the hosted mindroom.chat service (needs real pairing credentials), and running with a TLS-terminating proxy in front.

## Known Caveats

- The first activation clones two repos and builds the Cinny web UI inside the container; on slow networks the UI service can take several minutes after the switch returns.
  `systemctl --failed` plus the recovery commands in AGENTS.md cover the transient cases.
- `mindroom-lab` needs at least one real LLM provider key (in `agent-integrations.env.age`) before agents respond to messages.
- Nested virtualization (KVM/libvirt) is intentionally not enabled; a plain Incus container has no `/dev/kvm`.
