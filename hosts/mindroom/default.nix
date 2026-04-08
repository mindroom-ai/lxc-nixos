{ ... }:

{
  imports = [
    ../../modules/base-system.nix
    ../../modules/lxc-container.nix
    ../../modules/git-repo-checkouts.nix
    ../../modules/mindroom-runtime-services.nix
    ../../modules/agent-env.nix
    ./networking.nix
    ./secrets-config.nix
    ./mindroom.nix
    ./cinny.nix
    ./element.nix
    ./tuwunel.nix
    ./caddy.nix
  ];

  mindroom.runtime = {
    user = "mindroom";
    group = "mindroom";
    home = "/var/lib/mindroom";
    labStateDir = "/var/lib/mindroom/lab";
    chatStateDir = "/var/lib/mindroom/chat";
  };
}
