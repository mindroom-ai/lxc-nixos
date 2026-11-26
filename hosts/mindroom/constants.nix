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
  publicChatDomain = "chat.lab.mindroom.chat";
  tuwunelVersion = "v2.1.0-mindroom.1";
  tuwunelArchiveHash = "sha256-uhHwouWqBeDTY+jwljV0c3GZZEaOEhQh5M3Iu9tdbrw=";

  # Pinned commits for the runtime git checkouts. All pins in this file are
  # bumped daily by .github/workflows/update-pins.yml; to bump by hand run
  # scripts/update-pins.sh and rebuild.
  mindroomRev = "c3a51ef188e2bbe769e88515c16fe9e066547e14";
  mindroomChatRev = "d609004db2edb232d6e8d396a3eabf89f96682b6";
}
