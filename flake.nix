{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-wasmtime.url = "github:nixos/nixpkgs/d98abf5cf5914e5e4e9d57205e3af55ca90ffc1d";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      perSystem =
        {
          inputs',
          pkgs,
          system,
          ...
        }:
        let
          pinnedWasmtime = inputs'.nixpkgs-wasmtime.legacyPackages.wasmtime;
        in
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [
              (final: prev: {
                neovim-unwrapped =
                  (prev.neovim-unwrapped.overrideAttrs (prevAttrs: {
                    buildInputs = prevAttrs.buildInputs ++ [
                      final.wasmtime-29_0_1
                    ];
                    cmakeFlags = prevAttrs.cmakeFlags ++ [
                      (final.lib.cmakeBool "ENABLE_WASMTIME" true)
                    ];
                  })).override
                    {
                      tree-sitter = final.tree-sitter-with-wasm;
                    };

                tree-sitter-with-wasm = final.stdenv.mkDerivation {
                  inherit (prev.tree-sitter)
                    pname
                    version
                    src
                    cargoDeps
                    ;

                  buildInputs = [
                    final.wasmtime-29_0_1
                  ];
                  nativeBuildInputs = [
                    final.cmake
                    final.cargo
                    final.rustPlatform.cargoSetupHook
                    final.rustPlatform.cargoBuildHook
                    final.which
                  ];

                  cmakeDir = "../lib";
                  cmakeFlags = [ (final.lib.cmakeBool "TREE_SITTER_FEATURE_WASM" true) ];

                  cargoBuildType = "release";
                  cargoBuildFeatures = [ "wasm" ];

                  postInstall = "";
                  passthru = {
                    inherit (prev.tree-sitter.passthru)
                      grammars
                      buildGrammar
                      builtGrammars
                      withPlugins
                      allGrammars
                      ;
                  };

                  patches = (prev.tree-sitter.patches or [ ]) ++ [
                    (final.writeText "fuckoff.patch" ''
                      diff --git a/lib/tree-sitter.pc.in b/lib/tree-sitter.pc.in
                      index 60fe5c4a..1d099ec5 100644
                      --- a/lib/tree-sitter.pc.in
                      +++ b/lib/tree-sitter.pc.in
                      @@ -1,6 +1,5 @@
                      -prefix=@CMAKE_INSTALL_PREFIX@
                      -libdir=''${prefix}/@CMAKE_INSTALL_LIBDIR@
                      -includedir=''${prefix}/@CMAKE_INSTALL_INCLUDEDIR@
                      +libdir=@CMAKE_INSTALL_FULL_LIBDIR@
                      +includedir=@CMAKE_INSTALL_FULL_INCLUDEDIR@

                       Name: tree-sitter
                       Description: @PROJECT_DESCRIPTION@
                    '')
                  ];

                };

                wasmtime-29_0_1 = final.stdenv.mkDerivation {
                  inherit (pinnedWasmtime)
                    pname
                    version
                    src
                    cargoDeps
                    ;

                  nativeBuildInputs = [
                    final.cargo
                    final.rustc
                    final.cmake
                    final.rustPlatform.cargoSetupHook
                  ];

                  cmakeDir = "../crates/c-api";
                };
              })
            ];
            config = { };
          };

          devShells.default = pkgs.mkShell {
            buildInputs = with pkgs; [
              cargo
              cmake
              pkg-config
              rust-analyzer
              rust-bindgen
              rustc
              rustfmt
              wasmtime-29_0_1
            ];
          };

          packages = {
            inherit (pkgs)
              neovim
              neovim-unwrapped
              tree-sitter-with-wasm
              wasmtime-29_0_1
              ;
          };
        };
    };
}
