{ config, ... }:
{
  services.git-repo-checkouts = {
    enable = true;
    repositories.element = {
      path = "/srv/mindroom-element";
      url = "https://github.com/mindroom-ai/mindroom-element.git";
      branch = "develop";
      user = config.mindroom.runtime.user;
      group = config.mindroom.runtime.group;
      updateWhenClean = true;
    };
  };
}
