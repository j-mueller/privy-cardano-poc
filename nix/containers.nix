{ inputs, pkgs, lib, project, ... }:

lib.optionalAttrs pkgs.stdenv.isLinux (
  let
    projectFlake = project.flake {};
    cliPackage = projectFlake.packages."privy-cardano-api:exe:privy-cardano-cli";
    frontendStaticFiles = pkgs.buildNpmPackage {
      name = "privy-cardano-ui-static";
      src = lib.cleanSource ../src/ui;
      npmDepsHash = "sha256-YgRGeCvUnVs4KHuzs/Qul2i3bLqzDCiHxERZXwJAdJ8=";
      npmFlags = [ "--legacy-peer-deps" ];
      npmBuildScript = "build";
      installPhase = ''
        runHook preInstall
        mkdir -p "$out/share/privy-cardano-ui"
        cp -r build/* "$out/share/privy-cardano-ui/"
        runHook postInstall
      '';
    };

    n2cCompatPkgs = pkgs // {
      go = pkgs.go_1_24;
      buildGoModule = pkgs.buildGo124Module;
    };

    # Import the flake input source path directly to avoid import-from-derivation.
    n2cLib = import inputs.n2c.outPath { pkgs = n2cCompatPkgs; };

    skopeoContainersImagePatch = pkgs.fetchpatch2 {
      url = "https://github.com/nlewo/container-libs/commit/21b053ac62f3137de42585611953e923577d0e10.patch";
      sha256 = "sha256-pfwQh7FKWHY/xVAGMSvnjMOmkpMo9NG2HFZqhqZ1VN0=";
      postFetch = ''
        sed -i \
          -e '/^index /d' \
          -e '/^similarity index /d' \
          -e '/^dissimilarity index /d' \
          $out
      '';
    };

    patchedSkopeoN2C = n2cLib.skopeo-nix2container.overrideAttrs (_old: {
      preBuild = ''
        patch_file="$(mktemp)"
        cp ${skopeoContainersImagePatch} "$patch_file"
        sed -i 's#go.podman.io/image/v5#github.com/containers/image/v5#g' "$patch_file"
        mkdir -p vendor/github.com/nlewo/nix2container/
        cp -r ${n2cLib.nix2container-bin.src}/* vendor/github.com/nlewo/nix2container/
        chmod -R u+w vendor/github.com/nlewo/nix2container/nix
        sed -i 's#go.podman.io/image/v5#github.com/containers/image/v5#g' \
          vendor/github.com/nlewo/nix2container/nix/image.go
        cd vendor/github.com/containers/image/v5
        mkdir nix/
        touch nix/transport.go
        cat "$patch_file" | patch -p2
        cd -

        awk '
          $0 ~ /^# github.com\/containers\/image\/v5 / { print; in_mod=1; next }
          in_mod && /^## / { print; print "github.com/containers/image/v5/nix"; in_mod=0; next }
          { print }
        ' vendor/modules.txt > vendor/modules.txt.tmp
        mv vendor/modules.txt.tmp vendor/modules.txt

        echo '# github.com/nlewo/nix2container v1.0.0' >> vendor/modules.txt
        echo '## explicit; go 1.13' >> vendor/modules.txt
        echo github.com/nlewo/nix2container/nix >> vendor/modules.txt
        echo github.com/nlewo/nix2container/types >> vendor/modules.txt
        echo 'require (' >> go.mod
        echo '  github.com/nlewo/nix2container v1.0.0' >> go.mod
        echo ')' >> go.mod
      '';
    });

    writeSkopeoApplication = name: text:
      pkgs.writeShellApplication {
        inherit name text;
        runtimeInputs = [ patchedSkopeoN2C ];
        excludeShellChecks = [ "SC2068" ];
      };

    copyToDockerDaemon = image: writeSkopeoApplication "copy-to-docker-daemon" ''
      skopeo --insecure-policy copy nix:${image} docker-daemon:${image.imageName}:${image.imageTag} "$@"
    '';

    copyToRegistry = image: writeSkopeoApplication "copy-to-registry" ''
      skopeo --insecure-policy copy nix:${image} docker://${image.imageName}:${image.imageTag} "$@"
    '';

    copyToPodman = image: writeSkopeoApplication "copy-to-podman" ''
      skopeo --insecure-policy copy nix:${image} containers-storage:${image.imageName}:${image.imageTag} "$@"
    '';

    copyTo = image: writeSkopeoApplication "copy-to" ''
      skopeo --insecure-policy copy nix:${image} "$@"
    '';

    imageEnv = pkgs.buildEnv {
      name = "privy-cardano-cli-image-root";
      paths = with pkgs; [
        bashInteractive
        coreutils
        findutils
        gnused
        cacert
        cliPackage
        frontendStaticFiles
      ];
      pathsToLink = [
        "/bin"
        "/etc/ssl/certs"
        "/share/privy-cardano-ui"
      ];
    };

    entrypoint = pkgs.writeShellScriptBin "entrypoint" ''
      set -euo pipefail

      if [ -f ".env" ]; then
        set -a
        . ./.env
        set +a
      fi

      frontend_dir=""
      args=()

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --frontend-dir)
            if [ "$#" -lt 2 ]; then
              echo "Missing value for --frontend-dir" >&2
              exit 1
            fi
            frontend_dir="$2"
            shift 2
            ;;
          --frontend-dir=*)
            frontend_dir="''${1#--frontend-dir=}"
            shift
            ;;
          *)
            args+=("$1")
            shift
            ;;
        esac
      done

      if [ -z "$frontend_dir" ] && [ -d "/share/privy-cardano-ui" ]; then
        frontend_dir="/share/privy-cardano-ui"
      fi

      if [ -n "$frontend_dir" ] && [ -d "$frontend_dir" ]; then
        mkdir -p /tmp
        runtime_frontend_dir="$(mktemp -d /tmp/privy-cardano-ui.XXXXXX)"
        cp -r "$frontend_dir"/. "$runtime_frontend_dir"/

        replace_placeholder() {
          key="$1"
          value="''${!key:-}"

          if [ -z "$value" ]; then
            return 0
          fi

          escaped_value="$(printf '%s' "$value" | sed -e 's/[\\/&]/\\&/g')"
          find "$runtime_frontend_dir" -type f \
            \( -name "*.html" -o -name "*.js" -o -name "*.css" \) \
            -exec sed -i "s|__''${key}__|$escaped_value|g" {} +
        }

        replace_placeholder "VITE_PRIVY_APP_ID"
        replace_placeholder "VITE_PRIVY_CLIENT_ID"
        replace_placeholder "VITE_PRIVY_CARDANO_SERVER_URL"

        args+=("--frontend-dir" "$runtime_frontend_dir")
      fi

      exec /bin/privy-cardano-cli "''${args[@]}"
    '';

    imageRoot = pkgs.buildEnv {
      name = "privy-cardano-cli-image";
      paths = [
        imageEnv
        entrypoint
      ];
      pathsToLink = [
        "/bin"
        "/etc/ssl/certs"
        "/share/privy-cardano-ui"
      ];
    };

    rawImage = n2cLib.nix2container.buildImage {
      name = "privy-cardano-cli";
      tag = "latest";
      copyToRoot = imageRoot;
      config = {
        Entrypoint = [ "/bin/entrypoint" ];
        Env = [
          "PATH=/bin"
          "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
          "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
        ];
      };
    };

    dockerImage = rawImage // {
      passthru = rawImage.passthru // {
        copyToDockerDaemon = copyToDockerDaemon rawImage;
        copyToRegistry = copyToRegistry rawImage;
        copyToPodman = copyToPodman rawImage;
        copyTo = copyTo rawImage;
      };
      copyToDockerDaemon = copyToDockerDaemon rawImage;
      copyToRegistry = copyToRegistry rawImage;
      copyToPodman = copyToPodman rawImage;
      copyTo = copyTo rawImage;
    };

    runPodman = pkgs.writeShellApplication {
      name = "run-podman";
      runtimeInputs = [ pkgs.podman ];
      text = ''
        set -euo pipefail

        env_file=".env"
        podman_args=()
        if [ -f "$env_file" ]; then
          podman_args+=(-v "$PWD/$env_file:/work/.env:ro")
        else
          echo "Warning: no $env_file file found; starting container without it." >&2
        fi

        ${copyToPodman rawImage}/bin/copy-to-podman

        exec podman run --rm \
          -p 127.0.0.1:8080:8080 \
          -w /work \
          "''${podman_args[@]}" \
          "${rawImage.imageName}:${rawImage.imageTag}" \
          --frontend-dir ${frontendStaticFiles}/share/privy-cardano-ui
      '';
    };
  in
  {
    inherit dockerImage;
    inherit runPodman;
  }
)
