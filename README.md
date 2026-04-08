# MindRoom LXC NixOS

Standalone NixOS flake for the MindRoom Incus LXC container.

This repository preserves the current `mindroom` container shape:

- Incus LXC base configuration
- managed Git checkouts for `mindroom`, `mindroom-cinny`, and `mindroom-element`
- two MindRoom runtimes: `mindroom-lab` and `mindroom-chat`
- local Tuwunel Matrix homeserver
- Caddy routing for the app and Matrix endpoints
- Cinny and Element frontends

It intentionally excludes:

- all `openclaw` checkouts, services, overlays, and `signal-cli`
- personal users, SSH keys, hashed passwords, and home-manager state
- production secret values

## Repository Layout

- `hosts/mindroom/`: host-specific composition and app modules
- `modules/`: reusable standalone modules extracted from the larger dotfiles repo
- `secrets/shared/`: shared encrypted secret definitions
- `templates/`: plaintext templates used to seed new encrypted secrets
- `scripts/bootstrap-secrets.sh`: guided `ragenix` bootstrap for required secrets

## Create the Incus LXC

Create a basic NixOS LXC container in Incus first. The container should expose:

- a root filesystem named `rootfs`
- networking appropriate for your environment
- an SSH host key at `/etc/ssh/ssh_host_ed25519_key`

Then build and switch this flake inside the container or from a deployment host.

## Secrets Setup

This repository does not ship production secrets. Before activation, you must:

1. Edit `secrets/shared/secrets.nix` and add your operator key plus the target host SSH key.
2. Edit `hosts/mindroom/secrets/secrets.nix` and do the same for host-local secrets.
3. Run:

```bash
./scripts/bootstrap-secrets.sh mindroom
```

The bootstrap script opens `ragenix` for each required secret and pre-populates the plaintext editor buffer from the matching template:

- `templates/agent-integrations.env.example`
- `templates/agent-tooling.env.example`
- `templates/agent-runtime.env.example`
- `templates/registration-token.example`

The committed `.age` files are placeholders so the flake can evaluate and build.
Replace them before running `nixos-rebuild switch` on a real host.

## Build and Switch

Evaluate and build the host:

```bash
nix flake check
nix build .#nixosConfigurations.mindroom.config.system.build.toplevel
```

Switch on the target host:

```bash
sudo nixos-rebuild switch --flake .#mindroom
```

## Expected Services

After activation, these services should be present:

- `git-checkout-mindroom`
- `git-checkout-cinny`
- `git-checkout-element`
- `mindroom-lab`
- `mindroom-chat`
- `mindroom-cinny`
- `mindroom-element-build`
- `mindroom-element`
- `tuwunel`
- `caddy`
