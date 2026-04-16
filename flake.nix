{
  description = "Cydintosh — Macintosh Plus emulator for the ESP32 Cheap-Yellow-Display";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Tools PlatformIO expects on PATH, plus utilities the build script uses.
        # `pkgs.platformio` is the FHS-wrapped variant so its downloaded
        # dynamically-linked toolchains (uv, xtensa-esp-elf-gcc, etc.) just work
        # on NixOS.
        buildInputs = with pkgs; [
          platformio
          python3
          esptool
          git
          gnumake
          gcc
          curl
          cacert
          hfsutils
          coreutils
        ];

        ciBuild = pkgs.writeShellApplication {
          name = "cydintosh-ci-build";
          runtimeInputs = buildInputs;
          # The script is already set -euo pipefail; skip shellcheck noise.
          checkPhase = "";
          text = builtins.readFile ./scripts/ci-build.sh;
        };
      in {
        devShells.default = pkgs.mkShell {
          packages = buildInputs;

          shellHook = ''
            export PLATFORMIO_CORE_DIR="''${PLATFORMIO_CORE_DIR:-$PWD/.pio-core}"
            export PLATFORMIO_WORKSPACE_DIR="''${PLATFORMIO_WORKSPACE_DIR:-$PWD/.pio}"
            echo "Cydintosh dev shell ready."
            echo "  pio                 : $(command -v pio)"
            echo "  PLATFORMIO_CORE_DIR : $PLATFORMIO_CORE_DIR"
            echo ""
            echo "Run: bash scripts/ci-build.sh  (or: nix run .#ci-build)"
          '';
        };

        packages.ci-build = ciBuild;
        packages.default = ciBuild;
        apps.ci-build = {
          type = "app";
          program = "${ciBuild}/bin/cydintosh-ci-build";
        };
      });
}
