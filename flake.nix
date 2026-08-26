{
  description = "godot-onnx-loader: generic ONNX GDExtension for Godot 4.3 (mat490-style API)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        # Match CI + vizemes-align inference-smoke job. Nixpkgs onnxruntime links a
        # libonnxruntime.so.1 that requests an executable GNU_STACK; NixOS rejects
        # that at dlopen (Julian 2026-08-26). MS prebuilt does not.
        ortVersion = "1.20.1";
        ortTgz = pkgs.fetchurl {
          url = "https://github.com/microsoft/onnxruntime/releases/download/v${ortVersion}/onnxruntime-linux-x64-${ortVersion}.tgz";
          sha256 = "67db4dc1561f1e3fd42e619575c82c601ef89849afc7ea85a003abbac1a1a105";
        };
        ortMs = pkgs.runCommand "onnxruntime-ms-${ortVersion}" { } ''
          mkdir -p $out
          tar -C $out --strip-components=1 -xzf ${ortTgz}
        '';
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            gcc
            scons
            git
            curl
            python3
            godot_4
          ];
          shellHook = ''
            export ORT_ROOT="${ortMs}"
            export ORT_LIB="${ortMs}/lib"
            export C_INCLUDE_PATH="${ortMs}/include''${C_INCLUDE_PATH:+:}$C_INCLUDE_PATH"
            export LIBRARY_PATH="${ortMs}/lib''${LIBRARY_PATH:+:}$LIBRARY_PATH"
            export LD_LIBRARY_PATH="${ortMs}/lib''${LD_LIBRARY_PATH:+:}$LD_LIBRARY_PATH"
            export GODOT_BIN="${pkgs.godot_4}/bin/godot4"
            echo "godot-onnx-loader nix develop (ORT ${ortVersion} MS prebuilt — NixOS-safe dlopen)"
            echo "  ORT_ROOT=$ORT_ROOT"
            echo "  GODOT_BIN=$GODOT_BIN"
            echo "  git submodule update --init --recursive"
            echo "  scons platform=linux target=template_debug"
            echo "  scons smoke-csv"
            echo "  bash tools/godot_csv_smoke.sh"
            if [ ! -f "$ORT_ROOT/include/onnxruntime_c_api.h" ] && \
               [ ! -f "$ORT_ROOT/include/onnxruntime/onnxruntime_c_api.h" ]; then
              echo "  ERROR: onnxruntime_c_api.h not under ORT_ROOT" >&2
              exit 1
            fi
          '';
        };
      });
}
