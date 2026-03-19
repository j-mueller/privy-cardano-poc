{ inputs, system }:

let
  inherit (pkgs) lib;

  pkgs = import ./pkgs.nix { inherit inputs system; };

  utils = import ./utils.nix { inherit pkgs lib; };

  project = import ./project.nix { inherit inputs pkgs lib; };

  containers = import ./containers.nix { inherit inputs pkgs lib system project; };

  mkShell = { ghc, withHoogle ? true }: import ./shell.nix { inherit inputs pkgs lib project utils ghc system withHoogle; };

  packages =
    projectFlake.packages
    // lib.optionalAttrs pkgs.stdenv.isLinux {
      inherit (containers) dockerImage;
    };

  hydraPackages = lib.optionalAttrs pkgs.stdenv.isLinux {
    inherit (containers) dockerImage;
  };

  devShells = rec {
    default = ghc966; 
    ghc966 = mkShell { ghc = "ghc966"; }; 
    ghc966-nohoogle = mkShell { ghc = "ghc966"; withHoogle = false; }; 
    # ghc984 = mkShell { ghc = "ghc984"; }; 
    # ghc9102 = mkShell { ghc = "ghc9102"; }; 
    # ghc9122 = mkShell { ghc = "ghc9122"; }; 
  };

  projectFlake = project.flake {};

  apps = projectFlake.apps // {
    export-typescript-api = {
      type = "app";
      program = lib.getExe projectFlake.packages."privy-cardano-api:exe:export-typescript-api";
    };
    export-openapi-schema = {
      type = "app";
      program = lib.getExe projectFlake.packages."privy-cardano-api:exe:export-openapi-schema";
    };
    privy-cardano-cli = {
      type = "app";
      program = lib.getExe projectFlake.packages."privy-cardano-api:exe:privy-cardano-cli";
    };
  }
  // lib.optionalAttrs pkgs.stdenv.isLinux {
    privy-cardano-cli = {
      type = "app";
      program = lib.getExe containers.runPodman;
    };
  };

  defaultHydraJobs = { 
    ghc966 = projectFlake.hydraJobs.ghc966;
    # ghc984 = projectFlake.hydraJobs.ghc984;
    # ghc9102 = projectFlake.hydraJobs.ghc9102;
    # ghc9122 = projectFlake.hydraJobs.ghc9122;
    packages = hydraPackages;
    inherit devShells;
    required = utils.makeHydraRequiredJob hydraJobs; 
  };

  hydraJobsPerSystem = {
    "x86_64-linux"   = defaultHydraJobs; 
    "x86_64-darwin"  = defaultHydraJobs;
    "aarch64-linux"  = defaultHydraJobs; 
    "aarch64-darwin" = defaultHydraJobs;
  };

  hydraJobs = utils.flattenDerivationTree "-" hydraJobsPerSystem.${system};

in

{
  inherit devShells;
  inherit hydraJobs;
  inherit apps;
  inherit packages;
  # Explore the project via nix repl '.#'
  project = project;
  containers = containers;
}
