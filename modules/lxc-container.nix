# Container configuration for Incus LXC (not VM)
{ lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/virtualisation/lxc-container.nix") ];

  boot.isContainer = true;

  fileSystems."/" = {
    device = "rootfs";
    fsType = "none";
    options = [ "defaults" ];
  };

  # See: https://github.com/NixOS/nixpkgs/issues/157449
  boot.specialFileSystems."/run".options = [ "rshared" ];

  services.resolved.enable = true;
  networking.useHostResolvConf = lib.mkForce false;
  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
