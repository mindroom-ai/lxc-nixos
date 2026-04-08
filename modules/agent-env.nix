{ config, ... }:
let
  hostSecretsDir = ../hosts/${config.networking.hostName}/secrets;
  sharedSecretsDir = ../secrets/shared;
  runtimeUser = config.mindroom.runtime.user;
  runtimeGroup = config.mindroom.runtime.group;
in
{
  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  age.secrets.agent-runtime-env = {
    file = hostSecretsDir + "/agent-runtime.env.age";
    owner = runtimeUser;
    group = runtimeGroup;
    mode = "0400";
  };

  age.secrets.lab-runtime-env = {
    file = hostSecretsDir + "/lab-runtime.env.age";
    owner = runtimeUser;
    group = runtimeGroup;
    mode = "0400";
  };

  age.secrets.chat-runtime-env = {
    file = hostSecretsDir + "/chat-runtime.env.age";
    owner = runtimeUser;
    group = runtimeGroup;
    mode = "0400";
  };

  age.secrets.agent-integrations-env = {
    file = sharedSecretsDir + "/agent-integrations.env.age";
    owner = runtimeUser;
    group = runtimeGroup;
    mode = "0400";
  };

  age.secrets.agent-tooling-env = {
    file = sharedSecretsDir + "/agent-tooling.env.age";
    owner = runtimeUser;
    group = runtimeGroup;
    mode = "0400";
  };
}
