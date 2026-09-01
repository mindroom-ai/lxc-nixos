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
  tuwunelVersion = "v1.8.2-mindroom.4";
  tuwunelArchiveHash = "sha256-9tcp1BnaACaKwwRtCDmAU0//ZxCeFBqxGwOa8xMZRSU=";

  # Pinned commits for the runtime git checkouts. All pins in this file are
  # bumped daily by .github/workflows/update-pins.yml; to bump by hand run
  # scripts/update-pins.sh and rebuild.
  mindroomRev = "ab46d2beb4de7ee75662520d8b7fa6e3901fdb22";
  cinnyRev = "85600c3016bd168babdeb71d674f774f014cdd6c";
}
