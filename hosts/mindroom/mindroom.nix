{ config, ... }:
{
  services.git-repo-checkouts = {
    enable = true;
    repositories.mindroom = {
      path = "/srv/mindroom";
      url = "https://github.com/mindroom-ai/mindroom.git";
      branch = "main";
      user = config.mindroom.runtime.user;
      group = config.mindroom.runtime.group;
      updateWhenClean = true;
    };
  };
}
