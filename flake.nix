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
        in
        {
          inherit gamechat_mix;
          gamechat_balance = pkgs.callPackage ./nix/gamechat_balance.nix { };
          default = gamechat_mix;
        }
      );
    };
}
