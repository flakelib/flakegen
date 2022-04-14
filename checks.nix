{
  flakegen = {
    runCommand
  , nix-check
  , path
  , lib'mkFlake
  , self'generate
  , inputs
  }: let
    flakeConfig = removeAttrs (import ./flake.nix) [ "outputs" ];
    flake = lib'mkFlake flakeConfig;
    generated = self'generate {
      inherit flake;
    };
  in runCommand "flakegen" {
    nativeBuildInputs = [ nix-check ];
    inherit generated;
    outputsNix = "inputs: { }";
    passAsFile = [ "outputsNix" ];
    flakelib = inputs.flakelib;
    std = inputs.std;
    pkgs = path;
  } ''
    cat $generated > flake.nix
    cat $outputsNixPath > outputs.nix
    nix flake check \
      --override-input flakelib path:$flakelib \
      --override-input std path:$std \
      --override-input nixpkgs path:$pkgs \
      --no-build
    mkdir $out
    mv flake.nix outputs.nix $out/
  '';
}
