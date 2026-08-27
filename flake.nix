{
  description = "godot-onnx-loader: generic ONNX GDExtension for Godot 4.3 (mat490-style API)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        ortPkg = pkgs.onnxruntime;
        ortDev = pkgs.onnxruntime.dev;
        ortNix = pkgs.runCommand "onnxruntime-nix-${ortPkg.version}" { } ''
          mkdir -p $out/lib $out/include
          for f in ${ortPkg}/lib/libonnxruntime.so*; do
            ln -s "$f" $out/lib/
          done
          cp -r ${ortDev}/include/* $out/include/
        '';
        ortLibPath = pkgs.lib.makeLibraryPath [ ortPkg ];
        godotBin = "${pkgs.godot_4_6}/bin/godot4";
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            gcc
            scons
            git
            curl
            python3
          ];
          shellHook = ''
            export ORT_ROOT="${ortNix}"
            export ORT_LIB="${ortNix}/lib"
            export ONNX_ORT_BIN="${ortPkg}/lib"
            export ORT_BUNDLE=0
            export C_INCLUDE_PATH="${ortNix}/include''${C_INCLUDE_PATH:+:}$C_INCLUDE_PATH"
            export LIBRARY_PATH="${ortNix}/lib''${LIBRARY_PATH:+:}$LIBRARY_PATH"
            export LD_LIBRARY_PATH="${ortLibPath}''${LD_LIBRARY_PATH:+:}$LD_LIBRARY_PATH"
            export GODOT_BIN="${godotBin}"
            echo "godot-onnx-loader nix develop (ORT ${ortPkg.version} from 25.11 + godot_4_6 ${pkgs.godot_4_6.version})"
            echo "  ORT_ROOT=$ORT_ROOT"
            echo "  ONNX_ORT_BIN=$ONNX_ORT_BIN"
            echo "  GODOT_BIN=$GODOT_BIN"
            echo "  git submodule update --init --recursive"
            echo "  scons platform=linux target=template_debug"
            echo "  bash tools/godot_csv_smoke.sh"
            if [ ! -f "$ORT_ROOT/include/onnxruntime_c_api.h" ]; then
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
