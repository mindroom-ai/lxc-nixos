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

## Supported Host Setup

- The supported server-side path is: Linux host runs Incus, NixOS runs inside an
  Incus container.
- Per the official Incus docs, the Incus daemon is Linux-only. macOS and
  Windows provide only the client unless you target a remote Linux Incus host.
- Ubuntu 24.04 and later: `sudo apt install incus`
- Ubuntu 22.04: use the Zabbly Incus repository linked from the official docs
- Fedora: `sudo dnf install incus`
- After installing Incus, add your user to `incus-admin`, start a fresh shell,
  and initialize Incus:

```bash
sudo usermod -aG incus-admin "$USER"
newgrp incus-admin
incus admin init --minimal
```

Official references:

- https://linuxcontainers.org/incus/docs/main/installing/
- https://linuxcontainers.org/incus/docs/main/tutorial/first_steps/

## What Was Verified

Verified in this repo:

- `nix flake check`
- `nix build .#nixosConfigurations.mindroom.config.system.build.toplevel`
- package diff against the original dotfiles host: only `openclaw-cli` and
  `signal-cli` are intentionally missing
- secrets bootstrap failure path when recipients are not configured yet
- a disposable `nixos-rebuild switch` inside a fresh `images:nixos/unstable`
  Incus container using `path:/mnt/repo#mindroom` and `--option sandbox false`
- successful agenix decryption during activation
- `tuwunel`, `caddy`, `cinny`, and `element` service startup in the disposable
  container after the checkout/build jobs completed

Still not fully proven:

- `mindroom-lab` and `mindroom-chat` with real provider credentials and real
  runtime values
- nested virtualization inside the container; `libvirtd.service` still fails in
  a plain Incus container because `/dev/kvm` and DMI access are unavailable

Treat this as build-verified, disposable-container-tested, and still awaiting a
full production-value deployment.

## Repository Layout

- `hosts/mindroom/`: host-specific composition
- `modules/`: shared local modules used by the host
- `secrets/shared/`: shared encrypted secret files and recipients
- `hosts/mindroom/secrets/`: host-local encrypted secret files and recipients
- `templates/`: plaintext templates used when bootstrapping secrets
- `scripts/bootstrap-secrets.sh`: guided secret creation flow
- `AGENTS.md`: machine-oriented setup instructions

## Agent Quickstart

This is the fastest validated path if an operator or agent is driving the setup
from the Linux host that runs Incus.

### 1. Clone the Repo on the Incus Host

```bash
git clone https://github.com/mindroom-ai/lxc-nixos.git
cd lxc-nixos
```

### 2. Launch a Fresh NixOS Container

```bash
incus launch images:nixos/unstable mindroom -c security.nesting=true
incus config device add mindroom repo disk source="$PWD" path=/mnt/repo shift=true
```

Notes:

- `security.nesting=true` matches the existing container assumptions.
- The validated flow uses a host-mounted repo at `/mnt/repo`.
- When deploying from that mount, use `path:/mnt/repo#mindroom`, not
  `/mnt/repo#mindroom`. The `path:` prefix avoids Git ownership checks on the
  Incus-mounted filesystem.

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

From the Incus host:

```bash
incus exec mindroom -- /run/current-system/sw/bin/cat /etc/ssh/ssh_host_ed25519_key.pub
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

Run the bootstrap on any machine with Nix and `ragenix` available. If you do
not have `ragenix` installed already, the script tells you to run it through
Nix.

```bash
nix shell github:yaxitech/ragenix -c ./scripts/bootstrap-secrets.sh mindroom
```

The script opens `ragenix` once for each required secret and pre-populates the
plaintext buffer from the matching template:

- `templates/agent-integrations.env.example`
- `templates/agent-tooling.env.example`
- `templates/agent-runtime.env.example`
- `templates/lab-runtime.env.example`
- `templates/chat-runtime.env.example`
- `templates/registration-token.example`

Required encrypted files:

- `secrets/shared/agent-integrations.env.age`
- `secrets/shared/agent-tooling.env.age`
- `hosts/mindroom/secrets/agent-runtime.env.age`
- `hosts/mindroom/secrets/lab-runtime.env.age`
- `hosts/mindroom/secrets/chat-runtime.env.age`
- `hosts/mindroom/secrets/registration-token.age`

The host-local `lab` and `chat` runtime env files are now part of the secret
bootstrap flow. You no longer need unmanaged `/var/lib/mindroom/*/.env` files
for a fresh deployment, though optional local override files still work if you
create them yourself.

### 7. Preflight Checks

From the Incus host, verify GitHub is reachable from the container before the
first switch. The default checkout services clone from public GitHub repos at
activation time.

```bash
nix flake check
nix build .#nixosConfigurations.mindroom.config.system.build.toplevel
incus exec mindroom -- /run/current-system/sw/bin/curl -I https://github.com
```

If you see a warning about missing SSH authorized keys, go back to step 3.

### 8. Switch the Container

Run this from the Incus host:

```bash
incus exec mindroom -- /run/current-system/sw/bin/nixos-rebuild switch \
  --flake 'path:/mnt/repo#mindroom' \
  --option sandbox false
```

Notes:

- The stock NixOS Incus image needs `--option sandbox false` for this mounted
  repo workflow.
- If you clone the repo inside the container instead of mounting it from the
  host, use the normal flake path inside the container.
- The default host imports `modules/lxc-container.nix`; this repo assumes the
  target is an LXC container, not a bare-metal host.

## Detailed Setup

If you prefer not to use the host-mounted-repo flow, you can still clone the
repo directly inside the NixOS container and run:

```bash
/run/current-system/sw/bin/nixos-rebuild switch \
  --flake /path/to/lxc-nixos#mindroom \
  --option sandbox false
```

## Post-Deploy Checks

After `nixos-rebuild switch`, verify the important services:

```bash
incus exec mindroom -- /run/current-system/sw/bin/systemctl status git-checkout-mindroom --no-pager
incus exec mindroom -- /run/current-system/sw/bin/systemctl status git-checkout-cinny --no-pager
incus exec mindroom -- /run/current-system/sw/bin/systemctl status git-checkout-element --no-pager
incus exec mindroom -- /run/current-system/sw/bin/systemctl status mindroom-lab --no-pager
incus exec mindroom -- /run/current-system/sw/bin/systemctl status mindroom-chat --no-pager
incus exec mindroom -- /run/current-system/sw/bin/systemctl status mindroom-cinny --no-pager
incus exec mindroom -- /run/current-system/sw/bin/systemctl status mindroom-element-build --no-pager
incus exec mindroom -- /run/current-system/sw/bin/systemctl status mindroom-element --no-pager
incus exec mindroom -- /run/current-system/sw/bin/systemctl status tuwunel --no-pager
incus exec mindroom -- /run/current-system/sw/bin/systemctl status caddy --no-pager
```

Useful checks:

```bash
incus exec mindroom -- /run/current-system/sw/bin/systemctl --failed --no-pager
incus exec mindroom -- /run/current-system/sw/bin/journalctl -u mindroom-lab -n 100 --no-pager
incus exec mindroom -- /run/current-system/sw/bin/journalctl -u mindroom-chat -n 100 --no-pager
incus exec mindroom -- /run/current-system/sw/bin/journalctl -u tuwunel -n 100 --no-pager
incus exec mindroom -- /run/current-system/sw/bin/journalctl -u caddy -n 100 --no-pager
```

## Known Caveats

- In a plain Incus container, `libvirtd.service` is expected to fail because
  `/dev/kvm` and DMI access are not available. This does not block the MindRoom
  stack. If you want a clean `systemctl --failed`, remove
  `../../modules/virtualization.nix` from
  [default.nix](/home/basnijholt/Code/lxc-nixos/hosts/mindroom/default.nix) or
  adapt the container privileges for nested virtualization.
- If `git-checkout-element.service` or `mindroom-element-build.service` fail on
  the first activation, rerun:

```bash
incus exec mindroom -- /run/current-system/sw/bin/systemctl restart \
  git-checkout-element.service \
  mindroom-element-build.service \
  mindroom-element.service
```

- `mindroom-lab` and `mindroom-chat` need real values in
  `lab-runtime.env.age` and `chat-runtime.env.age`. The example templates are
  enough to prove decryption and service wiring, not enough to make the
  application useful.

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
