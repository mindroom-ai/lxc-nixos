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
  tuwunelVersion = "v1.9.4-mindroom.14";
  tuwunelArchiveHash = "sha256-NjmTXDV3hDgHlH2Js74XSV41vbYa7adRHlivK/axdQI=";

  # Pinned commits for the runtime git checkouts. All pins in this file are
  # bumped daily by .github/workflows/update-pins.yml; to bump by hand run
  # scripts/update-pins.sh and rebuild.
  mindroomRev = "659c43e229e9cbe76e695371dde82a41e3cbfda5";
  cinnyRev = "1014f4ddf71917559caf9663d239acc762de24c3";
}
