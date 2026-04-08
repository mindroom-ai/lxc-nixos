{ config, lib, pkgs, ... }:
let
  cfg = config.mindroom.runtime;
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
  };

  config = {
    system.stateVersion = "25.05";

    time.timeZone = lib.mkDefault "America/Los_Angeles";
    i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    services.openssh = {
      enable = true;
      openFirewall = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "prohibit-password";
        UseDns = false;
      };
    };

    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.home;
      createHome = true;
      useDefaultShell = true;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.home} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.labStateDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.chatStateDir} 0750 ${cfg.user} ${cfg.group} -"
    ];

    environment.systemPackages = with pkgs; [
      git
      vim
    ];
  };
}
