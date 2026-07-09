{ ... }:

{
  imports = [
    ../../modules/base-system.nix
    ../../modules/lxc-container.nix
    ../../modules/git-repo-checkouts.nix
    ../../modules/virtualization.nix
    ../../modules/mindroom-runtime-services.nix
    ../../modules/agent-env.nix
    ./networking.nix
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

    # MindRoom runs as two independent instances of the same application:
    #
    #  - lab:  agents that log in to the LOCAL Tuwunel homeserver inside this
    #          container. Self-contained; this is the one you want by default.
    #  - chat: agents that connect to the hosted mindroom.chat homeserver.
    #          Requires pairing credentials in chat-runtime.env.age, so leave
    #          it disabled unless you have them.
    lab.enable = true;
    chat.enable = false;

    # REQUIRED before deploying: at least one operator SSH public key.
    authorizedKeys = [
      # "ssh-ed25519 AAAA... you@example"
    ];
  };
}
