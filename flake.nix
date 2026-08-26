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
        ortPkg = pkgs.onnxruntime;
        ortDev = pkgs.lib.getDev ortPkg;
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            gcc
            scons
            git
            curl
            python3
            onnxruntime
          ];
          shellHook = ''
            export ORT_ROOT="${ortDev}"
            export ORT_LIB="${ortPkg}/lib"
            export C_INCLUDE_PATH="${ortDev}/include''${C_INCLUDE_PATH:+:}$C_INCLUDE_PATH"
            export LIBRARY_PATH="${ortPkg}/lib''${LIBRARY_PATH:+:}$LIBRARY_PATH"
            echo "godot-onnx-loader nix develop"
            echo "  ORT_ROOT=$ORT_ROOT"
            echo "  git submodule update --init --recursive"
            echo "  scons platform=linux target=template_debug"
            echo "  scons smoke-csv"
            echo "  Godot 4.3: open demo/ and run csv_smoke.tscn"
            if [ ! -f "$ORT_ROOT/include/onnxruntime_c_api.h" ] && \
               [ ! -f "$ORT_ROOT/include/onnxruntime/onnxruntime_c_api.h" ]; then
              echo "  ERROR: onnxruntime_c_api.h not under ORT_ROOT" >&2
              exit 1
            fi
          '';
        };
      });
}
