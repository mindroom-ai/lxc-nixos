# Container tooling (Docker, Incus, distrobox).
#
# libvirt/KVM is deliberately not enabled here: a plain Incus container has no
# /dev/kvm, so libvirtd would just sit in a failed state. If you run this
# configuration somewhere with working nested virtualization, add
# `virtualisation.libvirtd.enable = true;` in your host config.
{ pkgs, ... }:

{
  environment.systemPackages = [ pkgs.distrobox ];
  virtualisation.docker.enable = true;
  virtualisation.incus.enable = true;
}
