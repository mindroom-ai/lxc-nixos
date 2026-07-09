{ config, ... }:
let
  constants = import ./constants.nix;
  inherit (constants)
    publicCinnyDomain
    publicSiteDomain
    ;
  chatEnabled = config.mindroom.runtime.chat.enable;
in
{
  services.caddy = {
    enable = true;
    virtualHosts = {
      # All virtual hosts bind :80 on purpose: in the reference setup an
      # external reverse proxy (Traefik) terminates TLS for the public
      # hostnames and forwards plain HTTP to this container. If you have no
      # such proxy, drop the ":80" suffixes so Caddy provisions certificates
      # itself (requires public DNS + reachability on 80/443).
      "${publicSiteDomain}:80" = {
        extraConfig = ''
          route {
            # Served even though federation is disabled in Tuwunel; harmless,
            # and correct if federation is ever turned on.
            handle /.well-known/matrix/server {
              header Content-Type application/json
              respond 200 {
                body "{\"m.server\":\"${publicSiteDomain}:443\"}"
                close
              }
            }

            handle /.well-known/matrix/client {
              header Content-Type application/json
              respond 200 {
                body "{\"m.homeserver\":{\"base_url\":\"https://${publicSiteDomain}\"}}"
                close
              }
            }

            handle /_matrix/* {
              reverse_proxy 127.0.0.1:8008
            }

            handle /.well-known/matrix/* {
              respond "Not found" 404
            }

            ${
              if chatEnabled then
                ''
                  # The hosted-runtime backend (mindroom-chat) serves the app
                  # and the /v1/local-mindroom API on 8766.
                  handle {
                    reverse_proxy 127.0.0.1:8766
                  }
                ''
              else
                ''
                  # Without the chat runtime there is no app backend on this
                  # domain; only the Matrix API and well-known endpoints
                  # exist. The lab dashboard (127.0.0.1:8765) is deliberately
                  # not proxied: it is unauthenticated.
                  handle {
                    respond "Not found" 404
                  }
                ''
            }
          }
        '';
      };

      "${publicCinnyDomain}:80" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:8090
        '';
      };
    };
  };
}
