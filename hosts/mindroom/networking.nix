{ ... }:

{
  networking.hostName = "mindroom";
  networking.nftables.enable = true;
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
