{ config, ... }:
let
  constants = import ./constants.nix;
in
{
  services.git-repo-checkouts = {
    enable = true;
    repositories.cinny = {
      path = "/var/www/cinny";
      url = "https://github.com/mindroom-ai/mindroom-cinny.git";
      branch = "dev";
      rev = constants.cinnyRev;
      user = config.mindroom.runtime.user;
      group = config.mindroom.runtime.group;
    };
  };

  # Rebuild and restart the web UI when the pin moves (the build service
  # skips work when the checked-out revision matches its marker).
  systemd.services.mindroom-cinny-build.restartTriggers = [ constants.cinnyRev ];
  systemd.services.mindroom-cinny.restartTriggers = [ constants.cinnyRev ];
}
