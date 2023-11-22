{
  inputs = {
    nixpkgs = { };
    flakelib = {
      url = "github:flakelib/fl";
      inputs.std.follows = "std";
    };
    std.url = "github:flakelib/std";
  };
  outputs = { flakelib, ... }@inputs: flakelib {
    inherit inputs;
    config.name = "flakegen";
    builders = import ./builders.nix;
    checks = import ./checks.nix;
    lib = import ./lib.nix;
  };
}
