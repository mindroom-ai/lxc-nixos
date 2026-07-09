{ config, lib, ... }:
let
  cfg = config.mindroom.runtime;
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
      user = cfg.user;
      group = cfg.group;
      updateWhenClean = true;
    };
  };
}
