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
  tuwunelVersion = "v1.9.4-mindroom.19";
  tuwunelArchiveHash = "sha256-6gexwE82Q9TCnEVjRcZy9ceNPH2KkSQsJTmri+/TDvE=";

  # Pinned commits for the runtime git checkouts. All pins in this file are
  # bumped daily by .github/workflows/update-pins.yml; to bump by hand run
  # scripts/update-pins.sh and rebuild.
  mindroomRev = "ba77f2d85f745b5f42c6a1a5f52ef02306c9d16d";
  cinnyRev = "83bc0b00ef142660b0f8790471ebd3b7d68858b1";
}
