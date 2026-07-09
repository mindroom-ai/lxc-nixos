{ config, lib, ... }:
let
  cfg = config.mindroom.runtime;
  constants = import ./constants.nix;
in
{
  # The MindRoom source checkout is only needed when at least one agent
  # runtime is enabled.
  services.git-repo-checkouts = lib.mkIf (cfg.lab.enable || cfg.chat.enable) {
    enable = true;
    repositories.mindroom = {
      path = "/srv/mindroom";
      url = "https://github.com/mindroom-ai/mindroom.git";
      branch = "main";
      rev = constants.mindroomRev;
      user = cfg.user;
      group = cfg.group;
    };
  };

  # Restart the runtimes when the pin moves so `nixos-rebuild switch` applies
  # new code immediately; the checkout service re-runs first (After/Wants).
  systemd.services = lib.mkMerge [
    (lib.mkIf cfg.lab.enable {
      mindroom-lab.restartTriggers = [ constants.mindroomRev ];
    })
    (lib.mkIf cfg.chat.enable {
      mindroom-chat.restartTriggers = [ constants.mindroomRev ];
    })
  ];
}
