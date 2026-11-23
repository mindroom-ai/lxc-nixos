{
  description = "Standalone NixOS configuration for MindRoom (Incus LXC and microVM)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ragenix = {
      url = "github:yaxitech/ragenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      ragenix,
      microvm,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      system = "x86_64-linux";
      commonModules = [
        ragenix.nixosModules.default
        ./hosts/mindroom/default.nix
      ];
    in
    {
      nixosConfigurations = {
        mindroom = lib.nixosSystem {
          inherit system;
          modules = commonModules ++ [ ./modules/lxc-container.nix ];
        };

        mindroom-microvm = lib.nixosSystem {
          inherit system;
          modules = commonModules ++ [
            microvm.nixosModules.microvm
            ./modules/microvm-guest.nix
          ];
        };
      };

      packages.${system} = {
        # The pinned ragenix CLI, used by scripts/bootstrap-secrets.sh.
        ragenix = ragenix.packages.${system}.default;
        # QEMU microVM runner (build with `--out-link runner` from a private state dir; see AGENTS.md).
        mindroom-microvm = self.nixosConfigurations.mindroom-microvm.config.microvm.declaredRunner;
      };

      # Eval-only checks: `nix flake check` instantiates both targets (catching
      # every Nix-level error) without building their multi-GB closures.
      # unsafeDiscardOutputDependency keeps the .drv reference from pulling in
      # build outputs.
      checks.${system} =
        let
          pkgs = nixpkgs.legacyPackages.${system};
          evalCheck =
            name: drv:
            let
              drvPath = builtins.unsafeDiscardOutputDependency drv.drvPath;
            in
            pkgs.runCommand "${name}-eval-check" { } ''
              echo ${drvPath} > $out
            '';
        in
        {
          mindroom = evalCheck "mindroom" self.nixosConfigurations.mindroom.config.system.build.toplevel;
          mindroom-microvm = evalCheck "mindroom-microvm" self.packages.${system}.mindroom-microvm;
        };
    };
}
