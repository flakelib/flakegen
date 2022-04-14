{ lib, self'lib }: {
  modules = {
    flake = ./module.nix;
  };

  mkFlake = config: let
    eval = lib.evalModules {
      modules = [
        self'lib.modules.flake
        config
      ];
    };
  in eval.config.out.attrs // {
    inherit (eval) config options;
  };
}
