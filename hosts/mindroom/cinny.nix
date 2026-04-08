{ config, ... }:
{
  services.git-repo-checkouts = {
    enable = true;
    repositories.cinny = {
      path = "/var/www/cinny";
      url = "https://github.com/mindroom-ai/mindroom-cinny.git";
      branch = "dev";
      user = config.mindroom.runtime.user;
      group = config.mindroom.runtime.group;
      updateWhenClean = true;
      hardResetWhenDiverged = true;
    };
  };
}
