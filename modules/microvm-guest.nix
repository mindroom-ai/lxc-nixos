# Guest configuration for a standalone QEMU microVM (sibling of lxc-container.nix).
# Build and run from a private 0700 state directory OUTSIDE the git checkout
# (e.g. ~/.local/state/mindroom-microvm) using an absolute flake ref so disk
# images, control.sock, runner GC root, and ssh/ never enter the repo or /nix/store.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  lanMac = "02:00:00:00:00:01";
  hostKeyDir = "/etc/microvm-ssh";
  hostKeyPath = "${hostKeyDir}/ssh_host_ed25519_key";
  hostGit = "${config.microvm.vmHostPackages.git}/bin/git";
in
{
  microvm = {
    hypervisor = "qemu";
    vcpu = 4;
    # 8 GiB covers the first-boot MindRoom Chat Vite build (NODE_OPTIONS 4 GiB)
    # alongside uv installs, Tuwunel, and the tmpfs root.
    mem = 8192;
    # Fixed UUID so /etc/machine-id (32-hex) is stable and persistent journals
    # under /var/log/journal survive reboots; regenerate per deployment (e.g. `systemd-id128 new`).
    machineId = "b8689be6-ba91-9b35-6625-0f34607521a2";
    socket = "control.sock";

    preStart = ''
      if [ "$(${hostGit} rev-parse --is-inside-work-tree 2>/dev/null || true)" = "true" ]; then
        echo "Refusing to store VM state inside a git work tree; cd into a private state directory first (see AGENTS.md)." >&2
        exit 1
      fi
      if [ ! -f ssh/ssh_host_ed25519_key ]; then
        echo "Missing $PWD/ssh/ssh_host_ed25519_key; generate the VM host key in your private state directory first (see AGENTS.md)." >&2
        exit 1
      fi
      chmod 0700 .
      umask 077
    '';

    interfaces = [
      {
        type = "user";
        id = "usernet";
        mac = lanMac;
      }
    ];

    # Bound to loopback on the host; edit here if 8080 or 2222 is already in use.
    forwardPorts = [
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = 8080;
        guest.port = 80;
      }
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = 2222;
        guest.port = 22;
      }
    ];

    shares = [
      {
        # Share the host /nix/store read-only over 9p so the runner needs no
        # separate virtiofsd daemon and skips building a multi-GB store disk.
        proto = "9p";
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        readOnly = true;
      }
      {
        # Mount the pre-generated guest SSH host key read-only early in boot so
        # agenix decrypts secrets on first boot and sshd keeps a stable identity.
        proto = "9p";
        tag = "ssh-host-key";
        source = "ssh";
        mountPoint = hostKeyDir;
        readOnly = true;
      }
    ];

    # Overlay a writable ext4 volume on /nix/store so `nix shell`/`nix develop`
    # work inside the guest.
    writableStoreOverlay = "/nix/.rw-store";

    # Root is tmpfs; persistent state (/var incl. /var/lib/mindroom,
    # /var/lib/tuwunel, /var/www/cinny; /srv/mindroom; and the writable Nix
    # store overlay + DB) lives on sparse ext4 images created 0600 in $PWD.
    volumes = [
      {
        image = "var.img";
        label = "var";
        mountPoint = "/var";
        size = 20480;
      }
      {
        image = "srv.img";
        label = "srv";
        mountPoint = "/srv";
        size = 4096;
      }
      {
        image = "nix-store.img";
        label = "nix-store";
        mountPoint = "/nix/.rw-store";
        size = 8192;
      }
    ];
  };

  fileSystems."${hostKeyDir}".neededForBoot = true;
  fileSystems."/var".neededForBoot = true;

  # Persist the guest Nix DB alongside the writable store overlay on
  # nix-store.img before microvm.nix runs `nix-store --load-db`.
  boot.postBootCommands = lib.mkBefore ''
    ${pkgs.coreutils}/bin/mkdir -p /nix/.rw-store/var /nix/var/nix
    ${pkgs.util-linux}/bin/mountpoint -q /nix/var/nix || ${pkgs.util-linux}/bin/mount --bind /nix/.rw-store/var /nix/var/nix
  '';

  age.identityPaths = lib.mkForce [ hostKeyPath ];
  services.openssh.hostKeys = [
    {
      path = hostKeyPath;
      type = "ed25519";
    }
  ];

  # Only run DHCP on the QEMU virtio-net interface so systemd-networkd leaves
  # Docker/Incus bridges and veth pairs alone.
  networking.useDHCP = false;
  services.resolved.enable = true;
  systemd.network = {
    enable = true;
    networks."20-lan" = {
      matchConfig.MACAddress = lanMac;
      networkConfig.DHCP = "yes";
    };
    wait-online = {
      enable = true;
      anyInterface = true;
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
