{ config, lib, pkgs, ... }:
let
  cfg = config.mindroom.runtime;
  cliPowerTools = with pkgs; [
    _1password-cli
    act
    ragenix
    asciinema
    atuin
    bandwhich
    bat
    btop
    coreutils
    cups
    docker
    devbox
    devenv
    dnsutils
    duf
    eza
    fd
    fzf
    gh
    git
    git-filter-repo
    git-lfs
    git-secret
    gnugrep
    gnupg
    gnused
    gping
    hcloud
    htop
    iperf3
    jq
    just
    keyd
    lazydocker
    lazygit
    lm_sensors
    lsof
    micro
    mosh
    neovim
    nixfmt
    nmap
    ookla-speedtest
    packer
    parallel
    postgresql
    procs
    psmisc
    pwgen
    rclone
    ripgrep
    rsync
    starship
    tealdeer
    terraform
    tmux
    tokei
    tre-command
    tree
    typst
    unzip
    usbutils
    wakeonlan
    wget
    yazi-unwrapped
    yq-go
    zellij
    zoxide
  ];

  yaziPreviewDeps = with pkgs; [ file ];

  developmentToolchains = with pkgs; [
    bun
    gcc
    gnumake
    meson
    nodejs_20
    pkg-config
    portaudio
    (python3.withPackages (ps: [ ps.pipx ]))
  ];

  managedGroups =
    [ "wheel" ]
    ++ lib.optionals config.virtualisation.docker.enable [ "docker" ]
    ++ lib.optionals config.virtualisation.libvirtd.enable [ "libvirtd" ]
    ++ lib.optionals config.virtualisation.incus.enable [ "incus-admin" ];
in
{
  options.mindroom.runtime = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "mindroom";
      description = "User account that owns runtime state and managed checkouts.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "mindroom";
      description = "Primary group for the MindRoom runtime user.";
    };

    home = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/mindroom";
      description = "Home directory for the MindRoom runtime user.";
    };

    labStateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/mindroom/lab";
      description = "State directory for the lab runtime.";
    };

    chatStateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/mindroom/chat";
      description = "State directory for the hosted runtime.";
    };

    description = lib.mkOption {
      type = lib.types.str;
      default = "MindRoom Operator";
      description = "Description for the interactive operator account.";
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH authorized keys for the operator account.";
    };
  };

  config = {
    system.stateVersion = "25.05";

    time.timeZone = lib.mkDefault "America/Los_Angeles";
    i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

    nixpkgs.config.allowUnfree = true;

    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        cfg.user
      ];
    };

    boot.kernelModules = [ "tcp_bbr" ];
    boot.zfs.requestEncryptionCredentials = false;
    boot.kernel.sysctl = {
      "kernel.sysrq" = 1;
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.core.rmem_max" = 134217728;
      "net.core.wmem_max" = 134217728;
      "net.ipv4.tcp_rmem" = "4096 131072 134217728";
      "net.ipv4.tcp_wmem" = "4096 16384 134217728";
    };

    programs.nix-ld.enable = true;
    programs.nix-ld.libraries = with pkgs; [ portaudio ];

    services.openssh = {
      enable = true;
      openFirewall = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
        UseDns = false;
        X11Forwarding = true;
      };
    };

    services.fwupd.enable = true;
    services.syncthing.enable = true;
    services.tailscale.enable = true;
    services.earlyoom = {
      enable = true;
      freeSwapThreshold = 10;
      freeMemThreshold = 10;
    };

    programs.mosh.enable = true;
    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
    programs.zsh.enable = true;
    programs.direnv.enable = true;

    programs.ssh.knownHosts = {
      "truenas.local" = {
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJBFtTkkcsQ1KKBJ1ne2Q2COhfBSxs3H0ppO/HEirJt4";
      };
    };

    fonts.packages = with pkgs; [
      fira-code
      nerd-fonts.fira-code
      nerd-fonts.droid-sans-mono
      nerd-fonts.jetbrains-mono
      libertine
    ];

    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isNormalUser = true;
      description = cfg.description;
      group = cfg.group;
      extraGroups = managedGroups;
      home = cfg.home;
      createHome = true;
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.home} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.labStateDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.chatStateDir} 0750 ${cfg.user} ${cfg.group} -"
    ];

    environment.systemPackages =
      cliPowerTools
      ++ yaziPreviewDeps
      ++ developmentToolchains;

    warnings = lib.optional (cfg.authorizedKeys == [ ]) ''
      No SSH authorized keys are configured for ${cfg.user}. Add at least one key
      in hosts/mindroom/default.nix before deploying to a real container.
    '';
  };
}
