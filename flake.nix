{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-wasmtime.url = "github:nixos/nixpkgs/d98abf5cf5914e5e4e9d57205e3af55ca90ffc1d";
  };

  outputs =
    inputs@{ self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      flake.overlays.default =
        final: prev:
        let
          inherit (final.stdenv.targetPlatform.rust) cargoShortTarget;
          pinnedWasmtime = inputs.nixpkgs-wasmtime.legacyPackages.${final.stdenv.system}.wasmtime;
        in
        {
          neovim-unwrapped = prev.neovim-unwrapped.overrideAttrs (prevAttrs: {
            buildInputs = prevAttrs.buildInputs ++ [
              final.wasmtime-29_0_1
            ];
            cmakeFlags = prevAttrs.cmakeFlags ++ [
              (final.lib.cmakeBool "ENABLE_WASMTIME" true)
            ];
          });

          tree-sitter = prev.tree-sitter.overrideAttrs (prevAttrs: {
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

          wasmtime-29_0_1 = pinnedWasmtime.overrideAttrs {
            postInstall =
              ''
                # move libs from out to dev
                install -d -m 0755 $dev/lib
                install -m 0644 ''${!outputLib}/lib/* $dev/lib
                rm -r ''${!outputLib}/lib

                install -d -m0755 $dev/include/wasmtime
                # https://github.com/rust-lang/cargo/issues/9661
                install -m0644 \
                  target/${cargoShortTarget}/release/build/wasmtime-c-api-impl-*/out/include/*.h \
                  $dev/include
                install -m0644 \
                  target/${cargoShortTarget}/release/build/wasmtime-c-api-impl-*/out/include/wasmtime/*.h \
                  $dev/include/wasmtime
              ''
              + final.lib.optionalString final.stdenv.hostPlatform.isDarwin ''
                install_name_tool -id \
                  $dev/lib/libwasmtime.dylib \
                  $dev/lib/libwasmtime.dylib
              '';
          };
        };
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      perSystem =
        { pkgs, system, ... }:
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            config = { };
            overlays = [ self.overlays.default ];
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
            ];
          };

          packages = {
            inherit (pkgs)
              neovim
              neovim-unwrapped
              tree-sitter
              wasmtime
              wasmtime-29_0_1
              ;
          };
        };
    };
}
