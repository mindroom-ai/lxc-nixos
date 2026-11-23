# Guest configuration for a standalone QEMU microVM (sibling of lxc-container.nix).
# Runtime state (disk images, control socket, and the pre-generated SSH host key)
# lives under .microvm/ in the directory where `nix run .#mindroom-microvm` starts.
{ lib, ... }:

let
  lanMac = "02:00:00:00:00:01";
  hostKeyDir = "/etc/microvm-ssh";
  hostKeyPath = "${hostKeyDir}/ssh_host_ed25519_key";
in
{
  microvm = {
    hypervisor = "qemu";
    vcpu = 4;
    # 8 GiB covers the first-boot MindRoom Chat Vite build (NODE_OPTIONS 4 GiB)
    # alongside uv installs, Tuwunel, and the tmpfs root.
    mem = 8192;
    socket = ".microvm/control.sock";

    preStart = ''
      mkdir -p .microvm
      if [ ! -f .microvm/ssh/ssh_host_ed25519_key ]; then
        echo "Missing .microvm/ssh/ssh_host_ed25519_key; generate the VM host key first (see AGENTS.md)." >&2
        exit 1
      fi
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
        # Share the host /nix/store read-only over 9p so `nix run` needs no
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
        source = ".microvm/ssh";
        mountPoint = hostKeyDir;
        readOnly = true;
      }
    ];

    # Root is tmpfs; persistent state (/var incl. /var/lib/mindroom,
    # /var/lib/tuwunel, /var/www/cinny; and /srv/mindroom) lives on sparse ext4
    # images created on first start under .microvm/.
    volumes = [
      {
        image = ".microvm/var.img";
        label = "var";
        mountPoint = "/var";
        size = 20480;
      }
      {
        image = ".microvm/srv.img";
        label = "srv";
        mountPoint = "/srv";
        size = 4096;
      }
    ];
  };

  fileSystems."${hostKeyDir}".neededForBoot = true;
  fileSystems."/var".neededForBoot = true;

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
