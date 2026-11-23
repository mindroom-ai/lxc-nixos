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
  # shared /srv/mindroom venv under each other's feet. The wrapper forwards
  # its arguments to the mindroom CLI, so call sites pass subcommands.
  mindroom-uv =
    dir:
    pkgs.writeShellScript "mindroom-uv" ''
      # Put /run/wrappers/bin first so setuid wrappers (sudo) take precedence
      # over the non-setuid symlinks in /run/current-system/sw/bin.
      export PATH="/run/wrappers/bin:${pkgs.coreutils}/bin:${pkgs.uv}/bin:/run/current-system/sw/bin:$PATH"
      export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:''${LD_LIBRARY_PATH:-}"
      export UV_PROJECT_ENVIRONMENT="${dir}/.venv"
      exec uv run --python ${mindroomPython}/bin/python3 \
        --project "/srv/mindroom" \
        --directory "${dir}" \
        mindroom "$@"
    '';

  # Deny by default: track only config.yaml, .gitignore, and agent workspaces,
  # excluding credentials, secrets, caches, venvs, and runtime artifacts inside workspaces.
  setupGitignoreFile = pkgs.writeText "mindroom-setup-gitignore" ''
    *
    !/.gitignore
    !/config.yaml
    !/mindroom_data/
    !/mindroom_data/agents/
    !/mindroom_data/agents/*/
    !/mindroom_data/agents/*/workspace/
    !/mindroom_data/agents/*/workspace/**

    .ssh/
    .config/
    .npmrc
    .netrc
    .git-credentials
    .env*
    *.age
    *.pem
    *key*
    id_*
    credentials*
    .venv/
    node_modules/
    __pycache__/
    *.pyc
    .cache/
    *.db
    *.db-*
    *.sqlite
    *.sqlite*
    *.log
    *.lock
    mindroom_tool_outputs/
    .mindroom/
  '';

  # Standing instructions appended once to the starter agent's workspace
  # AGENTS.md, which MindRoom inlines into the system prompt via context_files.
  setupInstructionsFile =
    dir:
    pkgs.writeText "mindroom-setup-instructions.md" ''
      <!-- mindroom-nixos:setup -->
      ## Guest Environment and Version Control

      - **Root access:** You run as `${cfg.user}` with passwordless `sudo`, Docker, and Incus access — you have full root inside this container. Use `sudo -n ...` for privileged commands.
      - **Version-controlled setup:** Your MindRoom setup (`config.yaml` and agent workspaces under `mindroom_data/agents/*/workspace/`) is a Git repository at `${dir}`.
        - After every change you make to `config.yaml`, workspace files, memory, or skills, stage only the specific files you changed (`git -C ${dir} add <paths>`) and commit with a clear message (`git -C ${dir} commit -m "..."`). Never use `git add -A`.
        - Never commit secrets (`.env*`, `/run/agenix/*`, `.ssh/`, `.config/`, credentials, keys, or runtime databases — `.gitignore` excludes them; do not force-add them).
      - **System flake:** The NixOS deployment flake belongs to the operator on the host; do not modify or rebuild it from inside the guest.
    '';

  mkMindroomRuntime =
    {
      name,
      dir,
      matrixServerPreset,
      # The bundled dashboard/API server would bind 0.0.0.0 by default; keep
      # it on loopback and let Caddy decide what gets exposed.
      runArgs ? "run --api-host 127.0.0.1",
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
      path = with pkgs; [
        coreutils
        git
        gnugrep
      ];
      # First boot: run `mindroom config init` to generate config.yaml (reading
      # MINDROOM_OWNER_USER_ID from the agenix env), remove config init's starter
      # .env (without deleting any pre-existing operator .env), add standing
      # root/git instructions to the workspace AGENTS.md, and make the state dir
      # a git repo.
      preStart = ''
        if [ ! -f "${dir}/config.yaml" ]; then
          had_env=0
          [ -e "${dir}/.env" ] && had_env=1
          ${mindroom-uv dir} config init --no-input \
            --matrix-server ${matrixServerPreset} \
            --provider openai \
            --path "${dir}/config.yaml"
          if [ "$had_env" = 0 ]; then
            rm -f "${dir}/.env"
          fi
        fi

        workspace="${dir}/mindroom_data/agents/mind/workspace"
        if [ -f "$workspace/AGENTS.md" ] && ! grep -qF "<!-- mindroom-nixos:setup -->" "$workspace/AGENTS.md"; then
          echo "" >> "$workspace/AGENTS.md"
          cat "${setupInstructionsFile dir}" >> "$workspace/AGENTS.md"
        fi

        if ! git -C "${dir}" rev-parse -q --verify HEAD >/dev/null 2>&1; then
          if [ ! -f "${dir}/.gitignore" ]; then
            install -m 0644 "${setupGitignoreFile}" "${dir}/.gitignore"
          fi
          git -C "${dir}" init -b main
          git -C "${dir}" config user.name "MindRoom Agent"
          git -C "${dir}" config user.email "mindroom@localhost"
          git -C "${dir}" add -A
          git -C "${dir}" commit -m "Initial MindRoom setup"
        fi
      '';
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = dir;
        EnvironmentFile = agentEnvironmentFiles ++ extraEnvironmentFiles;
        Environment = [
          "MINDROOM_CONFIG_PATH=${dir}/config.yaml"
          "MINDROOM_STORAGE_PATH=${dir}/mindroom_data"
        ];
        ExecStart = "${mindroom-uv dir} ${runArgs}";
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
          runArgs = "run --api-host 127.0.0.1 --api-port 8766";
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
            nodejs_24
          ];
          serviceConfig = {
            Type = "oneshot";
            # Stay "active (exited)" after success so a bumped cinny pin
            # (via restartTriggers) re-runs the build at switch time.
            RemainAfterExit = true;
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = "/var/www/cinny";
            Restart = "on-failure";
            RestartSec = "10s";
          };
          script = ''
            set -euo pipefail

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
            ExecStart = "${pkgs.python3}/bin/python3 /var/www/cinny/scripts/serve.py 8090";
            Restart = "always";
            RestartSec = "5s";
          };
        };
      }
    ];
  };
}
