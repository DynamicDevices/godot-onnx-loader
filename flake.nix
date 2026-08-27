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
        ortVersion = "1.20.1";
        ortTgz = pkgs.fetchurl {
          url = "https://github.com/microsoft/onnxruntime/releases/download/v${ortVersion}/onnxruntime-linux-x64-${ortVersion}.tgz";
          sha256 = "67db4dc1561f1e3fd42e619575c82c601ef89849afc7ea85a003abbac1a1a105";
        };
        ortMs = pkgs.runCommand "onnxruntime-ms-${ortVersion}" { } ''
          mkdir -p $out
          tar -C $out --strip-components=1 -xzf ${ortTgz}
        '';
        # nixpkgs godot_4 aborts in ORT ReleaseSession (free(): invalid pointer).
        # Official upstream binary tears down cleanly once autoPatchelf'd for NixOS.
        godotVersion = "4.5.1";
        godotOfficial = pkgs.fetchzip {
          url = "https://github.com/godotengine/godot/releases/download/${godotVersion}-stable/Godot_v${godotVersion}-stable_linux.x86_64.zip";
          sha256 = "sha256-0B7p4Tl0eA1ENkERHz3kJKOhq2r5p0GUygCxQpf4S0E=";
        };
        godotOfficialRaw = "${godotOfficial}/Godot_v${godotVersion}-stable_linux.x86_64";
        # Pure NixOS cannot run unpatched upstream ELF (stub-ld). FHS wrapper for Julian + CI.
        godotWrapped = pkgs.buildFHSEnv {
          name = "godot-${godotVersion}-official";
          runScript = "${godotOfficialRaw} \"\$@\"";
        };
        godotBin = "${godotWrapped}/bin/godot-${godotVersion}-official";
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            gcc
            scons
            git
            curl
            python3
            patchelf
          ];
          shellHook = ''
            export ORT_ROOT="${ortMs}"
            export ORT_LIB="${ortMs}/lib"
            export C_INCLUDE_PATH="${ortMs}/include''${C_INCLUDE_PATH:+:}$C_INCLUDE_PATH"
            export LIBRARY_PATH="${ortMs}/lib''${LIBRARY_PATH:+:}$LIBRARY_PATH"
            export LD_LIBRARY_PATH="${ortMs}/lib''${LD_LIBRARY_PATH:+:}$LD_LIBRARY_PATH"
            export NIX_CXX_LIB="${pkgs.stdenv.cc.cc.lib}/lib"
            export GODOT_BIN="${godotBin}"
            echo "godot-onnx-loader nix develop (ORT ${ortVersion} MS + Godot ${godotVersion} official NixOS-wrapped)"
            echo "  ORT_ROOT=$ORT_ROOT"
            echo "  GODOT_BIN=$GODOT_BIN"
            echo "  NIX_CXX_LIB=$NIX_CXX_LIB  (for MS ORT libstdc++)"
            echo "  after scons: bash tools/patch_bundled_ort_rpath.sh"
            echo "  git submodule update --init --recursive"
            echo "  scons platform=linux target=template_debug"
            echo "  scons smoke-csv"
            echo "  bash tools/godot_csv_smoke.sh"
            if [ ! -f "$ORT_ROOT/include/onnxruntime_c_api.h" ] && \
               [ ! -f "$ORT_ROOT/include/onnxruntime/onnxruntime_c_api.h" ]; then
              echo "  ERROR: onnxruntime_c_api.h not under ORT_ROOT" >&2
              exit 1
            fi
            if [ ! -x "$GODOT_BIN" ]; then
              echo "  ERROR: GODOT_BIN not executable: $GODOT_BIN" >&2
              exit 1
            fi
          '';
        };
      });
}
