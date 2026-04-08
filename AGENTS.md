# Agent Setup Notes

Use this file when you need a machine-followable deployment path for the
default `mindroom` Incus container.

## Goal

Deploy the `mindroom` NixOS configuration into a fresh Incus container from a
Linux host.

## Preconditions

- The Incus server runs on Linux.
- The operator has shell access to the Incus host.
- The operator has an SSH public key to add to
  [default.nix](/home/basnijholt/Code/lxc-nixos/hosts/mindroom/default.nix).
- You can run `nix` somewhere for secret bootstrapping. That can be the host, a
  separate workstation, or the fresh NixOS container itself.

## Host Bootstrap

Ubuntu 24.04+:

```bash
sudo apt install incus
```

Fedora:

```bash
sudo dnf install incus
```

Then:

```bash
sudo usermod -aG incus-admin "$USER"
newgrp incus-admin
incus admin init --minimal
```

## Recommended Deployment Flow

1. Clone this repo on the Incus host.
2. Launch the container and mount the repo:

```bash
incus launch images:nixos/unstable mindroom -c security.nesting=true
incus config device add mindroom repo disk source="$PWD" path=/mnt/repo shift=true
```

3. Add the operator SSH key to
   [default.nix](/home/basnijholt/Code/lxc-nixos/hosts/mindroom/default.nix).
4. Read the container host SSH key:

```bash
incus exec mindroom -- /run/current-system/sw/bin/cat /etc/ssh/ssh_host_ed25519_key.pub
```

5. Put that key into:
   [secrets.nix](/home/basnijholt/Code/lxc-nixos/secrets/shared/secrets.nix)
   and
   [secrets.nix](/home/basnijholt/Code/lxc-nixos/hosts/mindroom/secrets/secrets.nix)
   alongside at least one operator key.
6. Bootstrap secrets:

```bash
nix shell github:yaxitech/ragenix -c ./scripts/bootstrap-secrets.sh mindroom
```

7. Run preflight checks:

```bash
nix flake check
nix build .#nixosConfigurations.mindroom.config.system.build.toplevel
incus exec mindroom -- /run/current-system/sw/bin/curl -I https://github.com
```

8. Deploy from the host-mounted repo:

```bash
incus exec mindroom -- /run/current-system/sw/bin/nixos-rebuild switch \
  --flake 'path:/mnt/repo#mindroom' \
  --option sandbox false
```

Important:

- Use `path:/mnt/repo#mindroom`, not `/mnt/repo#mindroom`.
- Keep `--option sandbox false` for this workflow on the stock NixOS Incus
  image.

## Required Secret Files

Shared:

- `secrets/shared/agent-integrations.env.age`
- `secrets/shared/agent-tooling.env.age`

Host-local:

- `hosts/mindroom/secrets/agent-runtime.env.age`
- `hosts/mindroom/secrets/lab-runtime.env.age`
- `hosts/mindroom/secrets/chat-runtime.env.age`
- `hosts/mindroom/secrets/registration-token.age`

The templates in `templates/` are only placeholders. They describe expected
keys, not valid production values.

## Post-Deploy Expectations

- `tuwunel`, `caddy`, `cinny`, and `element` should be the first things to
  verify.
- `mindroom-lab` and `mindroom-chat` only become useful once their runtime env
  secrets contain real values.
- `libvirtd.service` may fail in a plain Incus container. That is expected
  unless you deliberately provision nested virtualization support.

## Recovery Commands

If the Element checkout/build path fails during the first activation, rerun:

```bash
incus exec mindroom -- /run/current-system/sw/bin/systemctl restart \
  git-checkout-element.service \
  mindroom-element-build.service \
  mindroom-element.service
```

To inspect failures:

```bash
incus exec mindroom -- /run/current-system/sw/bin/systemctl --failed --no-pager
incus exec mindroom -- /run/current-system/sw/bin/journalctl -u mindroom-lab -n 100 --no-pager
incus exec mindroom -- /run/current-system/sw/bin/journalctl -u mindroom-chat -n 100 --no-pager
incus exec mindroom -- /run/current-system/sw/bin/journalctl -u mindroom-element-build -n 100 --no-pager
```
