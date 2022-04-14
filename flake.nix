{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flakelib.url = "github:flakelib/fl";
  };
  outputs = { flakelib, ... }@inputs: flakelib {
    inherit inputs;
    config.name = "flakegen";
    builders = import ./builders.nix;
    checks = import ./checks.nix;
    lib = import ./lib.nix;
  };
}
