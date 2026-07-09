{
  description = "Standalone NixOS configuration for the MindRoom Incus LXC";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ragenix = {
      url = "github:yaxitech/ragenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      ragenix,
      ...
    }:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      commonModules = [ ragenix.nixosModules.default ];
    in
    {
      nixosConfigurations.mindroom = lib.nixosSystem {
        inherit system;
        modules = commonModules ++ [ ./hosts/mindroom/default.nix ];
      };

      # The pinned ragenix CLI, used by scripts/bootstrap-secrets.sh.
      packages.${system}.ragenix = ragenix.packages.${system}.default;

      checks.${system}.mindroom = self.nixosConfigurations.mindroom.config.system.build.toplevel;
    };
}
