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
  tuwunelVersion = "v1.8.1-mindroom.2";
  tuwunelArchiveHash = "sha256-CIsjUzwTZ0rhc4plVwrTtKssvKpptvvhkBpi+j9N3uk=";

  # Pinned commits for the runtime git checkouts. All pins in this file are
  # bumped daily by .github/workflows/update-pins.yml; to bump by hand run
  # scripts/update-pins.sh and rebuild.
  mindroomRev = "6c4eb066f69a2d4efa9dd1074226275d1be53143";
  cinnyRev = "41b9600f871c298175dce796a3cc696f0af2f36e";
}
