{ ... }:
let
  constants = import ./constants.nix;
  inherit (constants)
    publicCinnyDomain
    publicSiteDomain
    ;
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

            handle /v1/local-mindroom/* {
              reverse_proxy 127.0.0.1:8766
            }

            handle {
              reverse_proxy 127.0.0.1:8766
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
