{
  description = "Pipewire implementation of the Game-Chat-Mix feature of gaming headsets";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          gamechat_mix = pkgs.callPackage ./nix/gamechat_mix.nix { };
          dms_plugin = pkgs.callPackage ./nix/dms_plugin.nix { inherit gamechat_mix; };
        in
        {
          inherit gamechat_mix dms_plugin;
          gamechat_balance = pkgs.callPackage ./nix/gamechat_balance.nix { };
          default = gamechat_mix;
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = [
            pkgs.bash
            pkgs.bats
            pkgs.gawk
            pkgs.nixfmt
            pkgs.pipewire
            pkgs.procps
            pkgs.pulseaudio
            pkgs.shellcheck
            pkgs.shfmt
            pkgs.util-linux
            pkgs.wireplumber
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
