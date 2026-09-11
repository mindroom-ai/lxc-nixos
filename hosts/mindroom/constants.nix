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
  tuwunelVersion = "v1.9.0-mindroom.3";
  tuwunelArchiveHash = "sha256-gsYt7W2pw8bgxaI7OLlM9BgkOFQ1h+ndOfEgGV2IN+Y=";

  # Pinned commits for the runtime git checkouts. All pins in this file are
  # bumped daily by .github/workflows/update-pins.yml; to bump by hand run
  # scripts/update-pins.sh and rebuild.
  mindroomRev = "0773a5328041671567d3b5231ae7dae982b9c3ad";
  cinnyRev = "c8a5029ffcb09507c3270cb2e8e4608f0ac924d3";
}
