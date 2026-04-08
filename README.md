# MindRoom LXC NixOS

Standalone NixOS flake for the MindRoom Incus LXC container.

This repo is meant to feel like the existing `mindroom` container from the
larger dotfiles tree, while intentionally excluding:

- all `openclaw` checkouts, overlays, services, and `signal-cli`
- personal SSH keys
- personal passwords
- production secret values

What it does include by default:

- the current `mindroom` host shape
- the shared baseline package set and service defaults from the dotfiles repo
- Docker, libvirt, Incus, and `distrobox`
- `mindroom-lab`, `mindroom-chat`, `cinny`, `element`, `tuwunel`, and `caddy`
- `ragenix`-based secrets wiring with templates and bootstrap tooling

## What Was Verified

Verified in this repo:

- `nix flake check`
- `nix build .#nixosConfigurations.mindroom.config.system.build.toplevel`
- package diff against the original dotfiles host: only `openclaw-cli` and
  `signal-cli` are intentionally missing
- secrets bootstrap failure path when recipients are not configured yet

Not yet verified end-to-end:

- a full `nixos-rebuild switch` inside a fresh Incus container
- successful service startup with real secrets and real host keys

Treat this as build-verified and setup-documented, not yet field-tested on a
fresh container with production values.

## Repository Layout

- `hosts/mindroom/`: host-specific composition
- `modules/`: shared local modules used by the host
- `secrets/shared/`: shared encrypted secret files and recipients
- `templates/`: plaintext templates used when bootstrapping secrets
- `scripts/bootstrap-secrets.sh`: guided secret creation flow

## Setup

### 1. Create the LXC

Create a basic NixOS Incus LXC first. At minimum, the container needs:

- a root filesystem mounted as `rootfs`
- network access
- an SSH host key at `/etc/ssh/ssh_host_ed25519_key`

This flake assumes the host is an LXC container and imports
`modules/lxc-container.nix`.

### 2. Clone the Repo

```bash
git clone https://github.com/mindroom-ai/lxc-nixos.git
cd lxc-nixos
```

### 3. Add Your Operator SSH Key

Edit [default.nix](/home/basnijholt/Code/lxc-nixos/hosts/mindroom/default.nix)
and put your SSH public key in `mindroom.runtime.authorizedKeys`.

Example:

```nix
  mindroom.runtime = {
    user = "mindroom";
    group = "mindroom";
    home = "/var/lib/mindroom";
    labStateDir = "/var/lib/mindroom/lab";
    chatStateDir = "/var/lib/mindroom/chat";
    authorizedKeys = [
      "ssh-ed25519 AAAA... you@example"
    ];
  };
```

Do this before deploying. Otherwise the build works, but you will not have SSH
access through the configured operator account.

### 4. Collect the Container Host SSH Key

Inside the target container, print the host public key:

```bash
sudo cat /etc/ssh/ssh_host_ed25519_key.pub
```

You will use this value as the host recipient in the next step.

### 5. Configure Secret Recipients

Edit these two files:

- [secrets.nix](/home/basnijholt/Code/lxc-nixos/secrets/shared/secrets.nix)
- [secrets.nix](/home/basnijholt/Code/lxc-nixos/hosts/mindroom/secrets/secrets.nix)

In both files:

- add at least one operator public key
- add the target container host public key

The repo ships placeholder recipient arrays and placeholder `.age` files only.

### 6. Bootstrap the Required Secrets

Run:

```bash
./scripts/bootstrap-secrets.sh mindroom
```

The script opens `ragenix` once for each required secret and pre-populates the
plaintext buffer from the matching template:

- `templates/agent-integrations.env.example`
- `templates/agent-tooling.env.example`
- `templates/agent-runtime.env.example`
- `templates/registration-token.example`

Required encrypted files:

- `secrets/shared/agent-integrations.env.age`
- `secrets/shared/agent-tooling.env.age`
- `hosts/mindroom/secrets/agent-runtime.env.age`
- `hosts/mindroom/secrets/registration-token.age`

### 7. Evaluate and Build

```bash
nix flake check
nix build .#nixosConfigurations.mindroom.config.system.build.toplevel
```

If you see a warning about missing SSH authorized keys, go back to step 3.

### 8. Switch the Host

Run this on the target container:

```bash
sudo nixos-rebuild switch --flake .#mindroom
```

If you are deploying from another machine, point `nixos-rebuild` at this repo
as usual for your workflow.

## Post-Deploy Checks

After `nixos-rebuild switch`, verify the important services:

```bash
systemctl status git-checkout-mindroom
systemctl status git-checkout-cinny
systemctl status git-checkout-element
systemctl status mindroom-lab
systemctl status mindroom-chat
systemctl status mindroom-cinny
systemctl status mindroom-element-build
systemctl status mindroom-element
systemctl status tuwunel
systemctl status caddy
```

Useful checks:

```bash
systemctl --failed
sudo journalctl -u mindroom-lab -n 100 --no-pager
sudo journalctl -u mindroom-chat -n 100 --no-pager
sudo journalctl -u tuwunel -n 100 --no-pager
sudo journalctl -u caddy -n 100 --no-pager
```

## Customization Points

The main host-specific values live in:

- [default.nix](/home/basnijholt/Code/lxc-nixos/hosts/mindroom/default.nix):
  operator user and runtime paths
- [constants.nix](/home/basnijholt/Code/lxc-nixos/hosts/mindroom/constants.nix):
  domains and Tuwunel release pin
- [mindroom.nix](/home/basnijholt/Code/lxc-nixos/hosts/mindroom/mindroom.nix):
  MindRoom checkout source
- [cinny.nix](/home/basnijholt/Code/lxc-nixos/hosts/mindroom/cinny.nix):
  Cinny checkout source
- [element.nix](/home/basnijholt/Code/lxc-nixos/hosts/mindroom/element.nix):
  Element checkout source

If you want this repo to diverge from the current container baseline, start
there.
