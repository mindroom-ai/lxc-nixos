let
  # This container serves the lab Matrix/app domain. TLS is NOT terminated
  # here: an external reverse proxy (Traefik in the reference setup) owns the
  # public *.lab.mindroom.chat certificates and forwards plain HTTP to this
  # container on port 80. If you deploy without such a proxy, change the Caddy
  # virtual hosts in caddy.nix to terminate TLS themselves.
  siteDomain = "mindroom.lab.mindroom.chat";
in
{
  inherit siteDomain;
  publicBaseDomain = "lab.mindroom.chat";
  publicSiteDomain = siteDomain;
  publicCinnyDomain = "chat.lab.mindroom.chat";
  publicElementDomain = "element.lab.mindroom.chat";
  tuwunelVersion = "v1.8.0-mindroom.5";
  tuwunelArchiveHash = "sha256-xaB2n7K2h+63M4eSDfJhgjUWeElVEf0L338amnr8pGI=";
}
