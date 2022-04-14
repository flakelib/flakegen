{
  generate = { runCommand, nix-check, lib }: { flake }: let
    placeholderToken = 1337;
    outputs =
      if flake ? outputs.import then ''inputs: import ${flake.outputs.import} inputs''
      else throw "unknown flake output";
  in runCommand "flake.nix" {
    passAsFile = [ "flake" ];
    nativeBuildInputs = [ nix-check ];
    replacement = outputs;
    inherit placeholderToken;
    flake = builtins.toJSON (removeAttrs flake [ "config" "options" ] // {
      outputs = placeholderToken;
    });
  } ''
    nix eval --impure --expr \
      "(builtins.fromJSON (builtins.readFile $flakePath))" |
      sed -e "s|$placeholderToken|$replacement|" > $out
  '';

  nix-check = { runCommand, nix, lib }: with lib; let
    nixString = v:
      if v == true then "true"
      else if v == false then "false"
      else if isList v then toString (map nixString v)
      else toString v;
    nixConfig = {
      experimental-features = [ "nix-command" "flakes" ];
      use-registries = false;
      #substitute = false;
      accept-flake-config = true;
      allow-symlinked-store = true;
    };
  in runCommand "nix-check" {
    inherit nix;
    passAsFile = [ "env" "commandNix" "commandNix2" "nixConfig" ];
    nixConfig = concatStringsSep "\n" (mapAttrsToList (k: v: "${k} = ${nixString v}") nixConfig);
    env = ''
      NIX_CHECK_ROOT=$TMPDIR/nix-check
      export XDG_CACHE_HOME=$NIX_CHECK_ROOT/cache
      export XDG_DATA_HOME=$NIX_CHECK_ROOT/data
      export XDG_CONFIG_HOME=$NIX_CHECK_ROOT/config
      NIX_CHECK_STORE=$NIX_CHECK_ROOT/store
      if [[ ! -e $NIX_CHECK_STORE ]]; then
        mkdir -p $NIX_CHECK_STORE
        ln -s $NIX_STORE/* $NIX_CHECK_STORE/
      fi
      export NIX_REMOTE= \
        NIX_STORE_DIR=$NIX_CHECK_STORE \
        NIX_DATA_DIR=$NIX_CHECK_ROOT/share \
        NIX_STATE_DIR=$NIX_CHECK_ROOT/state \
        NIX_CONF_DIR=$NIX_CHECK_ROOT/etc \
        NIX_LOG_DIR=$NIX_CHECK_ROOT/log \
        NIX_USER_CONF_FILES=''${NIX_USER_CONF_FILES-}:@out@/share/nix-check/config
    '';
    commandNix = ''
      source @out@/share/nix-check/env
      exec @nix@/bin/@basename@ "$@"
    '';
    commandNix2 = ''
      source @out@/share/nix-check/env
      ARGS=()
      if [[ ! -n ''${outputHash-} ]]; then
        ARGS+=(--offline)
      fi
      exec @nix@/bin/nix ''${ARGS[@]+"''${ARGS[@]}"} "$@"
    '';
  } ''
    mkdir -p $out/bin $out/share/nix-check
    substituteAll $envPath $out/share/nix-check/env
    ln -s $nix $out/share/nix-check/nix
    cp $nixConfigPath $out/share/nix-check/config
    substituteAll $commandNix2Path $out/bin/nix
    for basename in $(cd $nix/bin && echo nix-*); do
      substituteAll $commandNixPath $out/bin/$basename
    done
    chmod +x $out/bin/*
  '';

  makeCas = { runCommand }: {
    drv
  , hashes
  , version ? drv.version
  , mode ? "recursive" # or "flat"
  }: let
    hasHash = hashes ? version;
    hashAttrs = {
      outputHashMode = mode;
      outputHash = hashes.${version};
    };
    casDrv = runCommand "cas" ({
      inherit drv;
    } // hashAttrs) ''
      main() {
        if type -P cp > /dev/null; then
          cp -r $drv $out
          return
        fi

        cp() {
          < "$1" > "$2"
        }

        unimplemented() {
          echo $1 unimplemented >&2
          exit 1
        }

        rec() {
          if [[ -f $drv$1 ]]; then
            if [[ -x $drv$1 ]]; then
              unimplemented executables
            fi
            cp "$drv$1" "$out$1"
          elif [[ -d $drv$1 ]]; then
            mkdir "$out$1"
            for f in $(cd $drv$1 && echo *); do
              rec "$1/$f"
            done
          elif [[ -l $drv$1 ]]; then
            unimplemented symlinks
          else
            echo unknown file "$drv$1" >&2
            exit 1
          fi
        }
        rec ""
      }
      main
    '';
  in if ! hasHash then drv
  else if drv ? overrideAttrs then drv.overrideAttrs hashAttrs
  else drv // casDrv;

  appendCas = { writeShellScriptBin, jq'build }: let
  in writeShellScriptBin "append-cas" ''
    set -eu

    SOURCE_HASHES=$PWD/schema/source-hashes.json
    SOURCE="$1"
    SOURCE_REV="$2"
    SOURCE_HASH=$(nix --extra-experimental-features nix-command hash file --sri "$SOURCE")

    if [[ ! -e "$SOURCE_HASHES" ]]; then
      echo "hashfile does not exist: $SOURCE_HASHES" >&2
      exit 1
    fi

    EXPR=". + { \"$SOURCE_REV\":\"$SOURCE_HASH\" }"

    LOCKFILE=''${XDG_RUNTIME_DIR-/tmp}/base16-update-source.lock
    lock() { flock $1 99; }
    exec 99>$LOCKFILE
    trap 'set +e; lock -u; lock -xn && rm -f $LOCKFILE' EXIT

    lock -xn
    JSON="$(${jq'build}/bin/jq -M --sort-keys "$EXPR" "$SOURCE_HASHES")"
    printf "%s\n" "$JSON" > "$SOURCE_HASHES"
  '';
}
