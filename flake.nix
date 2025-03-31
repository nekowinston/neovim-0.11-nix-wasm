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

                tree-sitter-with-wasm = prev.tree-sitter.overrideAttrs (prevAttrs: {
                  buildInputs = (prevAttrs.buildInputs or [ ]) ++ [ final.wasmtime-29_0_1 ];
                  nativeBuildInputs = (prevAttrs.nativeBuildInputs or [ ]) ++ [ final.cmake ];

                  cmakeDir = "../lib";
                  cmakeFlags = [
                    (final.lib.cmakeBool "TREE_SITTER_FEATURE_WASM" true)
                    "-DCMAKE_INSTALL_INCLUDEDIR=include"
                    "-DCMAKE_INSTALL_LIBDIR=lib"
                  ];
                  cargoBuildFeatures = [ "wasm" ];

                  configurePhase = "cmakeConfigurePhase && cd ..";
                  postBuild = "cmake --build $cmakeBuildDir";

                  postInstall = ''
                    cmake --install $cmakeBuildDir
                    mv $out/share/pkgconfig $out/lib/pkgconfig
                    installShellCompletion --cmd tree-sitter \
                      --bash <("$out/bin/tree-sitter" complete --shell bash) \
                      --zsh <("$out/bin/tree-sitter" complete --shell zsh) \
                      --fish <("$out/bin/tree-sitter" complete --shell fish)
                  '';
                });

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
              tree-sitter
              tree-sitter-with-wasm
              wasmtime-29_0_1
              wasmtime
              ;
          };
        };
    };
}
