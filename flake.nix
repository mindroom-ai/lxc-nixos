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
      inherit (nixpkgs) lib;
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

      # Eval-only check: `nix flake check` instantiates the full system
      # (catching every Nix-level error) without building the multi-GB
      # closure. unsafeDiscardOutputDependency keeps the .drv reference from
      # pulling in the system's build outputs.
      checks.${system}.mindroom =
        let
          pkgs = nixpkgs.legacyPackages.${system};
          toplevelDrv = builtins.unsafeDiscardOutputDependency self.nixosConfigurations.mindroom.config.system.build.toplevel.drvPath;
        in
        pkgs.runCommand "mindroom-eval-check" { } ''
          echo ${toplevelDrv} > $out
        '';
    };
}
