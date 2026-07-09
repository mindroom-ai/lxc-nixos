{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mindroom.runtime;
  mindroomPython = pkgs.python314;

  # Load the shared agenix env bundles first so each runtime's own env can
  # override Matrix/provisioning values without editing the shared secrets.
  agentEnvironmentFiles = [
    config.age.secrets.agent-runtime-env.path
    config.age.secrets.agent-integrations-env.path
    config.age.secrets.agent-tooling-env.path
  ];

  # Each runtime gets its own uv environment so lab and chat never rebuild the
  # shared /srv/mindroom venv under each other's feet.
  mindroom-uv =
    dir: args:
    pkgs.writeShellScript "mindroom-uv" ''
      export PATH="${pkgs.coreutils}/bin:${pkgs.uv}/bin:/run/current-system/sw/bin:$PATH"
      export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:''${LD_LIBRARY_PATH:-}"
      export UV_PROJECT_ENVIRONMENT="${dir}/.venv"
      exec uv run --python ${mindroomPython}/bin/python3 \
        --project "/srv/mindroom" \
        --directory "${dir}" \
        mindroom ${args}
    '';

  mkMindroomRuntime =
    {
      name,
      dir,
      matrixServerPreset,
      runArgs ? "run",
      extraEnvironment ? [ ],
      extraEnvironmentFiles ? [ ],
    }:
    {
      description = "MindRoom AI Agent System (${name})";
      after = [
        "network-online.target"
        "git-checkout-mindroom.service"
      ];
      wants = [
        "network-online.target"
        "git-checkout-mindroom.service"
      ];
      wantedBy = [ "multi-user.target" ];
      # First boot: `mindroom run` refuses to start without a config.yaml, so
      # generate a starter config. The generated .env is truncated because it
      # contains placeholder values (e.g. MATRIX_HOMESERVER=...example.com)
      # that would override the agenix-provided environment; the empty file
      # remains available for manual local overrides.
      preStart = ''
        if [ ! -f "${dir}/config.yaml" ]; then
          ${mindroom-uv dir "config init --no-input --matrix-server ${matrixServerPreset} --path ${dir}/config.yaml"}
          : > "${dir}/.env"
        fi
      '';
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = dir;
        # The optional local .env comes last so it can override secret values.
        EnvironmentFile = agentEnvironmentFiles ++ extraEnvironmentFiles ++ [ "-${dir}/.env" ];
        Environment = [
          "MINDROOM_CONFIG_PATH=${dir}/config.yaml"
          "MINDROOM_STORAGE_PATH=${dir}/mindroom_data"
        ]
        ++ extraEnvironment;
        ExecStart = "${mindroom-uv dir runArgs}";
        Restart = "always";
        RestartSec = "10s";
        # The first start installs the uv environment for the /srv/mindroom
        # checkout; allow plenty of time on slow networks.
        TimeoutStartSec = "30min";
        TimeoutStopSec = "15s";
        KillMode = "mixed";
        SuccessExitStatus = "143 SIGTERM";
      };
    };

  # The element fork's package.json scripts invoke `pnpm` directly; route
  # those calls through corepack (bundled with nodejs) instead of shipping a
  # second package manager.
  pnpmShim = pkgs.writeShellScriptBin "pnpm" ''exec corepack pnpm "$@"'';
in
{
  options.mindroom.runtime = {
    lab.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable the self-contained "lab" runtime: MindRoom agents that log in
        to the local Tuwunel homeserver running inside this container.
      '';
    };

    chat.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable the hosted "chat" runtime: MindRoom agents that connect to the
        production mindroom.chat homeserver. Requires pairing credentials in
        chat-runtime.env.age, so it is off by default.
      '';
    };
  };

  config = {
    systemd.tmpfiles.rules =
      lib.optional cfg.lab.enable "d ${cfg.labStateDir} 0750 ${cfg.user} ${cfg.group} -"
      ++ lib.optional cfg.chat.enable "d ${cfg.chatStateDir} 0750 ${cfg.user} ${cfg.group} -";

    systemd.services = lib.mkMerge [
      (lib.mkIf cfg.lab.enable {
        mindroom-lab = mkMindroomRuntime {
          name = "lab";
          dir = cfg.labStateDir;
          matrixServerPreset = "self-hosted";
          extraEnvironmentFiles = [ config.age.secrets.lab-runtime-env.path ];
        };
      })

      (lib.mkIf cfg.chat.enable {
        mindroom-chat = mkMindroomRuntime {
          name = "mindroom.chat";
          dir = cfg.chatStateDir;
          matrixServerPreset = "mindroom.chat";
          runArgs = "run --api-port 8766";
          extraEnvironment = [ "BACKEND_PORT=8766" ];
          extraEnvironmentFiles = [ config.age.secrets.chat-runtime-env.path ];
        };
      })

      {
        mindroom-cinny-build = {
          description = "Build MindRoom Web UI (Cinny fork)";
          after = [
            "network-online.target"
            "git-checkout-cinny.service"
          ];
          wants = [
            "network-online.target"
            "git-checkout-cinny.service"
          ];
          wantedBy = [ "multi-user.target" ];
          path = with pkgs; [
            bash
            coreutils
            git
            nodejs_22
          ];
          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = "/var/www/cinny";
            Restart = "on-failure";
            RestartSec = "10s";
          };
          script = ''
            set -euo pipefail
            cd /var/www/cinny

            # The build marker lives inside .git/ so it never dirties the
            # working tree (a dirty tree would stop git-checkout-cinny from
            # pulling updates).
            current_rev="$(git rev-parse HEAD)"
            marker=.git/mindroom-dist-build-rev
            if [ -f dist/index.html ] && [ -f "$marker" ] && [ "$(cat "$marker")" = "$current_rev" ]; then
              exit 0
            fi

            export NODE_OPTIONS="--max-old-space-size=4096"
            npm ci
            npm run build
            echo "$current_rev" > "$marker"
          '';
        };

        mindroom-cinny = {
          description = "MindRoom Web UI (Cinny fork)";
          after = [
            "network-online.target"
            "git-checkout-cinny.service"
            "mindroom-cinny-build.service"
          ];
          wants = [
            "network-online.target"
            "git-checkout-cinny.service"
            "mindroom-cinny-build.service"
          ];
          requires = [ "mindroom-cinny-build.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = "/var/www/cinny/dist";
            ExecStart = "${pkgs.python3}/bin/python3 /var/www/cinny/serve.py 8090";
            Restart = "always";
            RestartSec = "5s";
          };
        };

        mindroom-element-build = {
          description = "Build MindRoom Web UI (Element fork)";
          after = [
            "network-online.target"
            "git-checkout-element.service"
          ];
          wants = [
            "network-online.target"
            "git-checkout-element.service"
          ];
          wantedBy = [ "multi-user.target" ];
          path = with pkgs; [
            bash
            coreutils
            git
            nodejs_22
            node-gyp
            pkg-config
            pnpmShim
          ];
          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = "/srv/mindroom-element";
            Restart = "on-failure";
            RestartSec = "10s";
          };
          script = ''
            set -euo pipefail
            cd /srv/mindroom-element

            # Marker lives inside .git/ so the tree stays clean and
            # git-checkout-element keeps pulling updates.
            current_rev="$(git rev-parse HEAD)"
            marker=.git/mindroom-webapp-build-rev
            if [ -f webapp/index.html ] && [ -f "$marker" ] && [ "$(cat "$marker")" = "$current_rev" ]; then
              exit 0
            fi

            cp config.mindroom.json config.json
            export NODE_OPTIONS="--max-old-space-size=4096"
            corepack pnpm install --frozen-lockfile
            corepack pnpm build
            echo "$current_rev" > "$marker"
          '';
        };

        mindroom-element = {
          description = "MindRoom Web UI (Element fork)";
          after = [
            "network-online.target"
            "git-checkout-element.service"
            "mindroom-element-build.service"
          ];
          wants = [
            "network-online.target"
            "git-checkout-element.service"
            "mindroom-element-build.service"
          ];
          requires = [ "mindroom-element-build.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = "/srv/mindroom-element/webapp";
            ExecStart = "${pkgs.python3}/bin/python3 /srv/mindroom-element/serve.py 8091";
            Restart = "always";
            RestartSec = "5s";
          };
        };
      }
    ];
  };
}
