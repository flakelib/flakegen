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

  parseRepoUrl = { url }: let
    type =
      if lib.hasPrefix "https://github.com/" url then "github"
      else if lib.hasPrefix "https://gitlab.com/" url then "gitlab"
      else if lib.hasPrefix "https://git.sr.ht/" url then "sourcehut"
      else "unknown";
    pattern = {
      github = ''https://github\.com/([^/]+)/(.+)'';
      gitlab = ''https://gitlab\.com/([^/]+)/(.+)'';
      sourcehut = ''https://git\.sr\.ht/~([^/]+)/(.+)'';
    }.${type};
    matches = builtins.match pattern url;
    owner = builtins.elemAt matches 0;
    repo = builtins.elemAt matches 1;
  in if type == "unknown" then { inherit type url; }
    else if matches == null then throw ''Failed to parse "${url}"''
    else { inherit type owner repo url; };

  flakeUrl = { repoUrl }: let
    fallback = "git+${repoUrl.url}";
    urls = {
      github = "github:${repoUrl.owner}/${repoUrl.repo}";
      gitlab = "gitlab:${repoUrl.owner}/${repoUrl.repo}";
      sourcehut = fallback; # ?ref=${repoUrl.branch or "main"}
    };
  in urls.${repoUrl.type} or fallback;
}
