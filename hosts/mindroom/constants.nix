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
  tuwunelVersion = "v2.1.0-mindroom.2";
  tuwunelArchiveHash = "sha256-NfXM/+yDu38AxX5gr5akZEvLKfzuW0Mul/n9uzkJi14=";

  # Pinned commits for the runtime git checkouts. All pins in this file are
  # bumped daily by .github/workflows/update-pins.yml; to bump by hand run
  # scripts/update-pins.sh and rebuild.
  mindroomRev = "4553e1b896fdd1ce072db1ccf2529b2dc31aa439";
  mindroomChatRev = "ef020d7a4ed713b6f1c81172050926ec66f8ff76";
}
