{ config, lib, ... }:
let
  cfg = config.mindroom.runtime;
  anyRuntimeEnabled = cfg.lab.enable || cfg.chat.enable;
  # Host secrets are looked up by hostname: renaming networking.hostName
  # requires renaming hosts/<name>/ to match, or evaluation fails here.
  hostSecretsDir = ../hosts/${config.networking.hostName}/secrets;
  sharedSecretsDir = ../secrets/shared;

  runtimeSecret = file: {
    inherit file;
    owner = cfg.user;
    group = cfg.group;
    mode = "0400";
  };
in
{
  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # Only reference secrets that an enabled runtime actually consumes, so a
  # deployment never fails on a secret it does not need.
  age.secrets = lib.mkMerge [
    (lib.mkIf anyRuntimeEnabled {
      agent-runtime-env = runtimeSecret (hostSecretsDir + "/agent-runtime.env.age");
      agent-integrations-env = runtimeSecret (sharedSecretsDir + "/agent-integrations.env.age");
      agent-tooling-env = runtimeSecret (sharedSecretsDir + "/agent-tooling.env.age");
    })
    (lib.mkIf cfg.lab.enable {
      lab-runtime-env = runtimeSecret (hostSecretsDir + "/lab-runtime.env.age");
    })
    (lib.mkIf cfg.chat.enable {
      chat-runtime-env = runtimeSecret (hostSecretsDir + "/chat-runtime.env.age");
    })
  ];
}
