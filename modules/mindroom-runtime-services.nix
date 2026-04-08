{
  config,
  pkgs,
  ...
}:
let
  runtimeUser = config.mindroom.runtime.user;
  runtimeGroup = config.mindroom.runtime.group;
  runtimeHome = config.mindroom.runtime.home;
  labStateDir = config.mindroom.runtime.labStateDir;
  chatStateDir = config.mindroom.runtime.chatStateDir;
  agentRuntimeEnvPath = config.age.secrets.agent-runtime-env.path;
  labRuntimeEnvPath = config.age.secrets.lab-runtime-env.path;
  chatRuntimeEnvPath = config.age.secrets.chat-runtime-env.path;
  agentIntegrationsEnvPath = config.age.secrets.agent-integrations-env.path;
  agentToolingEnvPath = config.age.secrets.agent-tooling-env.path;
  agentEnvironmentFiles = [
    agentRuntimeEnvPath
    agentIntegrationsEnvPath
    agentToolingEnvPath
  ];
in
{
  systemd.tmpfiles.rules = [
    "d ${runtimeHome} 0750 ${runtimeUser} ${runtimeGroup} -"
    "d ${labStateDir} 0750 ${runtimeUser} ${runtimeGroup} -"
    "d ${chatStateDir} 0750 ${runtimeUser} ${runtimeGroup} -"
  ];

  systemd.services = {
    mindroom-lab = {
      description = "MindRoom AI Agent System (lab)";
      after = [ "network-online.target" "git-checkout-mindroom.service" ];
      wants = [ "network-online.target" "git-checkout-mindroom.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = runtimeUser;
        Group = runtimeGroup;
        WorkingDirectory = labStateDir;
        EnvironmentFile = agentEnvironmentFiles ++ [
          labRuntimeEnvPath
          "-${labStateDir}/.env"
        ];
        Environment = [
          "MINDROOM_CONFIG_PATH=${labStateDir}/config.yaml"
          "MINDROOM_STORAGE_PATH=${labStateDir}/mindroom_data"
        ];
        ExecStart = "${pkgs.writeShellScript "run-mindroom-lab" ''
          export PATH="${pkgs.coreutils}/bin:${pkgs.uv}/bin:/run/current-system/sw/bin:$PATH"
          export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:''${LD_LIBRARY_PATH:-}"
          exec uv run --python ${pkgs.python313}/bin/python3 \
            --project "/srv/mindroom" \
            --directory "${labStateDir}" \
            mindroom run
        ''}";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    mindroom-chat = {
      description = "MindRoom AI Agent System (mindroom.chat)";
      after = [ "network-online.target" "git-checkout-mindroom.service" ];
      wants = [ "network-online.target" "git-checkout-mindroom.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = runtimeUser;
        Group = runtimeGroup;
        WorkingDirectory = chatStateDir;
        EnvironmentFile = agentEnvironmentFiles ++ [
          chatRuntimeEnvPath
          "-${chatStateDir}/.env"
        ];
        Environment = [
          "MINDROOM_CONFIG_PATH=${chatStateDir}/config.yaml"
          "MINDROOM_STORAGE_PATH=${chatStateDir}/mindroom_data"
          "BACKEND_PORT=8766"
        ];
        ExecStart = "${pkgs.writeShellScript "run-mindroom-chat" ''
          export PATH="${pkgs.coreutils}/bin:${pkgs.uv}/bin:/run/current-system/sw/bin:$PATH"
          export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:''${LD_LIBRARY_PATH:-}"
          exec uv run --python ${pkgs.python313}/bin/python3 \
            --project "/srv/mindroom" \
            --directory "${chatStateDir}" \
            mindroom run --api-port 8766
        ''}";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    mindroom-cinny = {
      description = "MindRoom Web UI (Cinny fork)";
      after = [ "network-online.target" "git-checkout-cinny.service" ];
      wants = [ "network-online.target" "git-checkout-cinny.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = runtimeUser;
        Group = runtimeGroup;
        WorkingDirectory = "/var/www/cinny/dist";
        ExecStart = "${pkgs.python3}/bin/python3 /var/www/cinny/serve.py 8090";
        Restart = "always";
        RestartSec = "5s";
      };
    };

    mindroom-element-build = {
      description = "Build MindRoom Web UI (Element fork)";
      after = [ "network-online.target" "git-checkout-element.service" ];
      wants = [ "network-online.target" "git-checkout-element.service" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        bash
        coreutils
        git
        nodejs_22
        node-gyp
        pkg-config
      ];
      serviceConfig = {
        Type = "oneshot";
        User = runtimeUser;
        Group = runtimeGroup;
        WorkingDirectory = "/srv/mindroom-element";
        Restart = "on-failure";
        RestartSec = "10s";
      };
      script = ''
        set -euo pipefail
        cd /srv/mindroom-element

        current_rev="$(git rev-parse HEAD)"
        if [ -f webapp/index.html ] && [ -f .webapp-build-rev ] && [ "$(cat .webapp-build-rev)" = "$current_rev" ]; then
          exit 0
        fi

        cp config.mindroom.json config.json
        tmp_bin=".tmp-bin"
        trap 'rm -rf "$tmp_bin"' EXIT
        mkdir -p "$tmp_bin"
        cat > "$tmp_bin/pnpm" <<'EOF'
#!/usr/bin/env sh
exec corepack pnpm "$@"
EOF
        chmod +x "$tmp_bin/pnpm"
        export PATH="$PWD/$tmp_bin:$PATH"
        corepack pnpm install --frozen-lockfile
        corepack pnpm build
        echo "$current_rev" > .webapp-build-rev
      '';
    };

    mindroom-element = {
      description = "MindRoom Web UI (Element fork)";
      after = [ "network-online.target" "git-checkout-element.service" "mindroom-element-build.service" ];
      wants = [ "network-online.target" "git-checkout-element.service" "mindroom-element-build.service" ];
      requires = [ "mindroom-element-build.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = runtimeUser;
        Group = runtimeGroup;
        WorkingDirectory = "/srv/mindroom-element/webapp";
        ExecStart = "${pkgs.python3}/bin/python3 /srv/mindroom-element/serve.py 8091";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
