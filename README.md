# MindRoom NixOS (Incus LXC & MicroVM)

<picture>
  <source media="(prefers-reduced-motion: no-preference)" srcset="https://raw.githubusercontent.com/mindroom-ai/mindroom/main/assets/logo/logo-mark-animated.svg" />
  <img src="https://raw.githubusercontent.com/mindroom-ai/mindroom/main/assets/logo/logo-mark.svg" alt="MindRoom Logo" align="right" width="120" />
</picture>

Standalone NixOS flake for running the MindRoom stack as either an Incus LXC container (`#mindroom`) or a standalone QEMU microVM via `microvm.nix` (`#mindroom-microvm`): local Matrix homeserver, web client, and the MindRoom AI agent runtime, with all secrets managed through `ragenix`.

**To deploy, follow [AGENTS.md](AGENTS.md)** — it is the canonical step-by-step runbook, written to be followed verbatim by a human or an agent.
This README explains what you get and which knobs exist.

## What Runs Inside the Guest

| Service | Purpose | Port |
| --- | --- | --- |
| `tuwunel` | Local Matrix homeserver (MindRoom Tuwunel fork, pinned release binary) | 8008 (loopback) |
| `caddy` | HTTP reverse proxy / routing for the public hostnames | 80 |
| `mindroom-cinny` | MindRoom Chat web client (built in-guest on first activation) | 8090 (all interfaces; not open in the guest firewall) |
| `mindroom-lab` | MindRoom agent runtime — local homeserver (optional, default on) | 8765 (loopback; unauthenticated dashboard/API, not proxied) |
| `mindroom-chat` | MindRoom agent runtime — hosted mindroom.chat (optional, default off) | 8766 (loopback; proxied by Caddy when enabled) |
| `git-checkout-*` | Keep the MindRoom and MindRoom Chat checkouts at the pinned revisions | — |

The guest also ships Docker, Incus, distrobox, and a CLI/dev toolbox for the operator account and the agents.

## Deployment Targets

Both targets share [hosts/mindroom/default.nix](hosts/mindroom/default.nix) and run the exact same service stack:

- **Incus LXC (`nixosConfigurations.mindroom`)**: deploys into an `images:nixos/unstable` Incus container with [modules/lxc-container.nix](modules/lxc-container.nix).
- **QEMU MicroVM (`nixosConfigurations.mindroom-microvm`)**: boots directly on any `x86_64-linux` host with `/dev/kvm` from a private `0700` state directory outside the checkout (`nix build --out-link runner /path/to/repo#mindroom-microvm && ./runner/bin/microvm-run`, keeping a GC root for the live host store paths), configured in [modules/microvm-guest.nix](modules/microvm-guest.nix):
  - 4 vCPU, 8 GiB RAM (sized for the first-boot MindRoom Chat Vite build and `uv` installs alongside the tmpfs root).
  - Shares the host `/nix/store` read-only over 9p with a persistent writable overlay and Nix DB (`nix-store.img`, 8 GiB sparse ext4, persisting `/nix/.rw-store` and `/nix/var/nix`) so `nix shell` / `nix develop` work inside the guest and guest-added store paths stay registered across reboots.
  - Persists `/var` (20 GiB sparse ext4: Tuwunel DB, MindRoom state/venvs, MindRoom Chat checkout/build, journals, Docker/Incus) and `/srv` (4 GiB sparse ext4: MindRoom source checkout) as `0600` images in the private state directory, with a pinned `microvm.machineId` so journals survive reboots.
  - Mounts a pre-generated SSH host key from `ssh/` in that private state directory read-only with `neededForBoot = true`, so `agenix` decrypts secrets on first boot and `sshd` keeps a stable host identity across reboots (without putting key material inside the git checkout).
  - Uses QEMU user networking forwarding `127.0.0.1:8080 -> 80` (Caddy) and `127.0.0.1:2222 -> 22` (SSH).
  - Docker and Incus from [modules/virtualization.nix](modules/virtualization.nix) work inside the VM; unlike LXC, a microVM *could* also enable nested KVM/libvirt (`virtualisation.libvirtd.enable = true`), though it stays disabled by default.

## One Application, Two Runtimes

MindRoom runs as up to two independent instances of the same application, toggled in [hosts/mindroom/default.nix](hosts/mindroom/default.nix):

- **lab** (`mindroom.runtime.lab.enable`, default `true`): agents that register and log in on the **local Tuwunel homeserver inside this guest**, using the registration token you create during secret bootstrap.
  Fully self-contained — this is the one you want when trying the repo out.
- **chat** (`mindroom.runtime.chat.enable`, default `false`): agents that connect out to the **hosted mindroom.chat homeserver**.
  Requires pairing credentials (`MINDROOM_LOCAL_CLIENT_ID/SECRET`) in `chat-runtime.env.age`, so leave it off unless you have them.

Each enabled runtime gets its own state directory, `config.yaml`, uv environment, and encrypted env file; they share the two org-wide secret bundles (`agent-integrations`, `agent-tooling`).
Secrets are only required for runtimes you actually enable.

## Security Model

The container or microVM is the security boundary, and everything inside it is deliberately trusted:
the agents run as the operator account, which has passwordless sudo and Docker access, so **agents have root inside the guest by design**.
Treat the guest as expendable, and do not put anything inside it that the agents must not touch.
The guest firewall opens TCP 80 (Caddy), TCP 22 (SSH), and UDP 60000–61000 (mosh); Tuwunel and the runtime APIs listen on loopback. On the microVM, QEMU only forwards host loopback `127.0.0.1:8080 -> 80` and `127.0.0.1:2222 -> 22`.

For the default microVM configuration specifically:
QEMU user (SLIRP) networking lets the guest reach the host's `127.0.0.1` loopback services via `10.0.2.2`, and the 9p `ro-store` share exposes the host's entire `/nix/store` to the guest.
Run the defaults only on a host without sensitive loopback-only services or secrets in `/nix/store`.
To harden it, switch to `microvm.storeOnDisk = true` (instead of sharing the host `/nix/store`) and `tap` networking (instead of QEMU `user` networking).

## Version Pinning and Updates

Everything that runs is pinned in [hosts/mindroom/constants.nix](hosts/mindroom/constants.nix): the Tuwunel release (`tuwunelVersion` + hash) and the exact commits of the MindRoom and MindRoom Chat checkouts (`mindroomRev`, `cinnyRev`).
The `update-pins` GitHub workflow bumps all three to the latest upstream daily and pushes only after `nix flake check` passes; run [scripts/update-pins.sh](scripts/update-pins.sh) to do the same by hand.
Applying an update to a running container is `git pull` in the repo clone plus the same `nixos-rebuild switch` used to deploy — the checkout services move to the new pins and the affected services restart (a MindRoom Chat pin bump rebuilds the web UI, which adds a few minutes to the switch).
A checkout with local changes is never touched, so in-container experiments survive switches; clean checkouts are reset to the pinned commit.

## TLS Model (Read This Before Exposing Anything)

Caddy binds **port 80 only**.
In the reference setup an external reverse proxy (Traefik) owns the certificates for the public `*.lab.mindroom.chat` hostnames and forwards plain HTTP to this container.
The well-known responses advertise `https://` URLs on that assumption.

If you have no TLS-terminating proxy in front, do not expose port 80 to the internet as-is.
Either put one there, or remove the `":80"` suffixes in [hosts/mindroom/caddy.nix](hosts/mindroom/caddy.nix) so Caddy provisions certificates itself (needs public DNS and reachability on 80/443).

## Repository Layout

- `hosts/mindroom/` — host composition: domains/pins (`constants.nix`), runtime toggles and SSH keys (`default.nix`), per-service config
- `modules/` — reusable modules (base system, LXC and microVM guest glue, git checkouts, runtime services, secrets wiring)
- `secrets/shared/` + `hosts/mindroom/secrets/` — encrypted secrets and their recipient lists (the repo ships placeholders only)
- `templates/` — plaintext templates that seed each secret during bootstrap
- `scripts/bootstrap-secrets.sh` — guided secret creation
- `AGENTS.md` — the deployment runbook

## Customization Points

- [hosts/mindroom/default.nix](hosts/mindroom/default.nix): runtime toggles, operator SSH keys, state paths
- [modules/microvm-guest.nix](modules/microvm-guest.nix): microVM vCPU/RAM, forwarded host ports, volume sizes
- [hosts/mindroom/constants.nix](hosts/mindroom/constants.nix): public domains, the Tuwunel release pin, and the MindRoom/MindRoom Chat commit pins
- [hosts/mindroom/mindroom.nix](hosts/mindroom/mindroom.nix), [cinny.nix](hosts/mindroom/cinny.nix): which repos are checked out and which pins they follow

Changing the public domains in `constants.nix` is not enough by itself: `MATRIX_SERVER_NAME` inside `lab-runtime.env.age` must match, and MindRoom Chat bakes its homeserver defaults into its own build, so a full domain change also needs a matching client-side change.

## What Was Verified

Verified end-to-end on 2026-11-22 by booting a fresh `mindroom-microvm` QEMU guest on an `x86_64-linux` NixOS host with `/dev/kvm`, following the MicroVM runbook in AGENTS.md literally (with `microvm.forwardPorts` adjusted to `18080`/`12222` because `8080`/`2222` were already bound on the test host):

- `nix flake check` (eval-only for both `#mindroom` and `#mindroom-microvm`), `nixfmt --check`, and `shellcheck`
- pre-boot host key generation in a `0700` state directory outside the checkout, `0600` disk image creation via runner `umask 077`, non-interactive secret bootstrap via `nix shell .#ragenix -c ./scripts/bootstrap-secrets.sh --non-interactive --values-dir ...` with a live `OPENAI_API_KEY`, and agenix decryption on first boot
- `nix build --out-link runner "$REPO#mindroom-microvm" && ./runner/bin/microvm-run` first boot (~2m total for checkouts, MindRoom Chat UI build, and `mindroom-lab` `uv` install) settling with `systemctl --failed` empty and `tuwunel`, `caddy`, `mindroom-cinny`, `mindroom-lab`, `docker`, `incus` active
- writable `/nix/store` overlay + persisted `/nix/var/nix` DB: `nix build --no-link --print-out-paths nixpkgs#hello` on boot 1 and `nix path-info --offline <path>` after reboot succeeding as `mindroom`
- host access over the forwarded HTTP port to both the Matrix client API (`Host: mindroom.lab.mindroom.chat`) and the MindRoom Chat web UI (`Host: chat.lab.mindroom.chat`, HTTP 200)
- `mindroom-lab` registering `@mindroom_user`, `@mindroom_router`, and `@mindroom_mind` on local Tuwunel; registering a local test user with the bootstrap token, replacing the pairing placeholder in `/var/lib/mindroom/lab/config.yaml`, and receiving an actual LLM reply from `@mindroom_mind`
- clean shutdown (`./runner/bin/microvm-shutdown`) and reboot persistence: SSH host key, checkouts, built UI (no rebuild on second boot), Tuwunel database/accounts, room history, and multi-boot persistent journal (`journalctl --list-boots` showing 2 boots) survived intact

Not verified for the microVM: the `chat` runtime against hosted `mindroom.chat` and an external TLS-terminating reverse proxy.

Verified end-to-end on 2026-07-08 by deploying a fresh `images:nixos/unstable` Incus container from this repo, following AGENTS.md literally:

- `nix flake` evaluation and full toplevel build
- secret bootstrap via `nix shell .#ragenix -c ./scripts/bootstrap-secrets.sh` (including the refusal path when recipients are missing) and agenix decryption inside the container at activation
- `nixos-rebuild switch --flake 'path:/mnt/repo#mindroom'` from the host-mounted repo
- `tuwunel`, `caddy` up; Matrix client API answering through Caddy
- the in-container MindRoom Chat build (`mindroom-cinny-build`) and the web UI serving through Caddy
- `mindroom-lab` starting, installing its uv environment from the `/srv/mindroom` checkout, and registering agents on the local homeserver with the bootstrap registration token

Not verified: agent conversations with real LLM provider keys, the `chat` runtime against the hosted mindroom.chat service (needs real pairing credentials), and running with a TLS-terminating proxy in front.

## Known Caveats

- The first activation clones two repos and builds the MindRoom Chat web UI inside the container; on slow networks the UI service can take several minutes after the switch returns.
  `systemctl --failed` plus the recovery commands in AGENTS.md cover the transient cases.
- `mindroom-lab` needs at least one real LLM provider key (in `agent-integrations.env.age`) before agents respond to messages.
- Nested virtualization (KVM/libvirt) is intentionally not enabled; a plain Incus container has no `/dev/kvm` (a microVM could enable `virtualisation.libvirtd.enable = true` if needed).
