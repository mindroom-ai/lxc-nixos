{
  config,
  lib,
  pkgs,
  ...
}:
let
  constants = import ./constants.nix;
  inherit (constants) siteDomain tuwunelVersion tuwunelArchiveHash;

  tuwunelArchive = pkgs.fetchurl {
    url = "https://github.com/mindroom-ai/mindroom-tuwunel/releases/download/${tuwunelVersion}/tuwunel-${tuwunelVersion}-linux-x86_64.tar.gz";
    hash = tuwunelArchiveHash;
  };

  tuwunelPackage =
    pkgs.runCommand "tuwunel-${tuwunelVersion}-linux-x86_64"
      {
        nativeBuildInputs = with pkgs; [
          findutils
          gnutar
          gzip
        ];
      }
      ''
        mkdir -p "$out/bin"
        tar -xzf "${tuwunelArchive}" -C "$TMPDIR"
        bin_path="$(find "$TMPDIR" -maxdepth 2 -type f -name tuwunel | head -n1)"
        if [ -z "$bin_path" ]; then
          echo "no 'tuwunel' binary found in the release archive; its layout changed" >&2
          exit 1
        fi
        install -m 0755 "$bin_path" "$out/bin/tuwunel"
      '';

  # Token-gated registration; the token is loaded from an agenix-managed file.
  tuwunelConfig = pkgs.writeText "tuwunel.toml" ''
    [global]
    server_name = "${siteDomain}"
    database_path = "/var/lib/tuwunel"
    address = ["127.0.0.1", "::1"]
    port = 8008
    allow_registration = true
    registration_token_file = "${config.age.secrets.registration-token.path}"
    allow_federation = false
    max_request_size = 25165824
  '';
in
{
  age.secrets.registration-token = {
    file = ./secrets/registration-token.age;
    owner = "tuwunel";
    group = "tuwunel";
    mode = "0400";
  };

  users.users.tuwunel = {
    isSystemUser = true;
    group = "tuwunel";
    home = "/var/lib/tuwunel";
  };
  users.groups.tuwunel = { };

  systemd.services.tuwunel = {
    description = "Tuwunel Matrix Homeserver (MindRoom local)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "tuwunel";
      Group = "tuwunel";
      ExecStart = "${tuwunelPackage}/bin/tuwunel";
      Restart = "on-failure";
      RestartSec = "5s";

      StateDirectory = "tuwunel";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ "/var/lib/tuwunel" ];
      LimitNOFILE = 65536;
    };

    environment = {
      # Tuwunel still reads the CONDUWUIT_-prefixed variables from its
      # conduwuit lineage.
      CONDUWUIT_CONFIG = "${tuwunelConfig}";
      LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.liburing ];
    };
  };
}
