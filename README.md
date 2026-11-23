# MindRoom LXC NixOS

<picture>
  <source media="(prefers-reduced-motion: no-preference)" srcset="https://raw.githubusercontent.com/mindroom-ai/mindroom/main/assets/logo/logo-mark-animated.svg" />
  <img src="https://raw.githubusercontent.com/mindroom-ai/mindroom/main/assets/logo/logo-mark.svg" alt="MindRoom Logo" align="right" width="120" />
</picture>

Deploy a self-contained MindRoom stack — local Matrix homeserver, MindRoom Chat web UI, reverse proxy, and AI agent runtime — in an Incus LXC container.
Secrets are encrypted and managed with `agenix` and `ragenix`.

## Quick Start

**[AGENTS.md](AGENTS.md) is the setup runbook**, written for AI coding agents (or humans) to follow verbatim from container launch to verified deployment.

Paste this prompt into your coding agent:

```text
Clone https://github.com/mindroom-ai/lxc-nixos and follow AGENTS.md to deploy MindRoom.
```

**What you need:**

- A Linux host running (or able to install) Incus
- Nix (on the host, a workstation, or the container) for secret bootstrap
- An SSH key pair for operator access and secret encryption
- An LLM API key (such as `OPENAI_API_KEY`) so agents can reply

## What's Included

| Service | What it does |
| --- | --- |
| `tuwunel` | Local Matrix homeserver (MindRoom's Tuwunel fork) |
| `caddy` | HTTP reverse proxy routing the public hostnames |
| `mindroom-cinny` | MindRoom Chat web UI, built inside the container on first activation |
| `mindroom-lab` | MindRoom AI agent runtime for the local homeserver (default on) |
| `mindroom-chat` | MindRoom AI agent runtime for hosted `mindroom.chat` (default off) |
| `git-checkout-*` | Keeps the MindRoom and MindRoom Chat source checkouts at pinned commits |

The container also includes Docker, Incus, distrobox, and CLI dev tools for the operator and agents.

## Two Runtimes: Lab vs. Chat

- **Lab (`mindroom.runtime.lab.enable`, default on):** Self-contained setup where agents register and chat on the local Tuwunel homeserver inside the container.
- **Chat (`mindroom.runtime.chat.enable`, default off):** Connects agents to hosted `mindroom.chat`; requires pairing credentials.

## Good to Know

- **Security boundary:** The container is the sandbox — agents run as the operator user with root and Docker access inside it by design, so treat the container as expendable (see [Security Model](AGENTS.md#security-model)).
- **HTTPS / TLS:** Caddy listens on plain HTTP port 80 only; put a TLS-terminating reverse proxy in front before exposing publicly (see [TLS Model](AGENTS.md#tls-model)).
- **Updates:** Pinned versions update daily via GitHub Actions; `git pull` plus `nixos-rebuild switch` applies them while leaving local checkout edits untouched (see [Version Pinning and Updates](AGENTS.md#version-pinning-and-updates)).
- **Looking for a microVM instead?** See [mindroom-ai/microvm-nixos](https://github.com/mindroom-ai/microvm-nixos) to deploy the same stack in a standalone QEMU microVM.

## Repository Layout

- `flake.nix` — NixOS flake for the container system config and pinned `ragenix`
- `hosts/mindroom/` — host configuration, version pins, runtime toggles, and per-service configs
- `modules/` — LXC container wiring, base system, git checkouts, runtime services, and dev tooling
- `secrets/` + `hosts/mindroom/secrets/` — encrypted secrets and recipient lists (placeholders only in git)
- `templates/` — plaintext templates used to seed secrets during bootstrap
- `scripts/` — `bootstrap-secrets.sh` and `update-pins.sh`
- [AGENTS.md](AGENTS.md) — step-by-step deployment runbook and full technical reference
