_:

{
  networking = {
    hostName = "mindroom";
    nftables.enable = true;
    firewall.enable = true;
    # Caddy binds port 80 only (TLS terminates outside this container); add
    # 443 here if you switch Caddy to terminate TLS itself.
    firewall.allowedTCPPorts = [ 80 ];
  };
}
