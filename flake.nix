{
  description = "Nix flake for Firefox nightly.";

  inputs = {
    gecko-dev = {
      url = github:mozilla/gecko-dev/211b017ce99b573d742afe52c6e88b8734654dfb;
      flake = false;
    };
    nss = { url = github:calbrecht/f4s-nss; inputs.nixpkgs.follows = "nixpkgs"; };
    nixpkgs = { url = github:nixos/nixpkgs/nixos-unstable; };
  };

  outputs = { self, nixpkgs, gecko-dev, nss }:
    let
      ffversion = "90.0a1-20210529214400";

      system = "x86_64-linux";

      pkgs = nixpkgs.legacyPackages."${system}";

      overrides = {
        nss = nss.legacyPackages."${system}".nss;

        rust-cbindgen = pkgs.rust-cbindgen.overrideAttrs (old: rec {
          name = "rust-cbindgen-${version}";
          version = "0.19.0";

          src = pkgs.fetchFromGitHub {
            owner = "eqrion";
            repo = "cbindgen";
            rev = "v${version}";
            sha256 = "sha256-AGTwjwwHFmQOoCFg7bIu2fcxEYSzeGhmbaHSkulsoxw=";
          };

          nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.pythonPackages.cython ];

          cargoDeps = old.cargoDeps.overrideAttrs (pkgs.lib.const {
            name = "${name}-vendor.tar.gz";
            inherit src;
            outputHash = "sha256-qOaJVBmeEFdNbgYTW9rtHfwzua+6tSHmDCMeG3EE3GM=";
          });

          checkFlags = [
            # https://github.com/NixOS/nixpkgs/pull/65303
            "--skip test_bitfield"
            "--skip test_expand"
            "--skip test_expand"
            "--skip test_expand_default_features"
            "--skip test_expand_dep"
            "--skip test_expand_dep_v2"
            "--skip test_expand_features"
            "--skip test_expand_no_default_features"
            "--skip lib_default_uses_debug_build"
            "--skip lib_explicit_debug_build"
            "--skip lib_explicit_release_build"
          ];
        });
      };
    in
    {
      legacyPackages."${system}" = self.overlay self.legacyPackages."${system}" pkgs;

      overlay = final: prev: {
        firefox-nightly = prev.wrapFirefox final.firefox-nightly-unwrapped {
          version = ffversion;
        };
        firefox-wayland-nightly = prev.wrapFirefox final.firefox-nightly-unwrapped {
          version = ffversion;
          forceWayland = true;
        };
        firefox-nightly-unwrapped =
          (prev.firefox-unwrapped.override overrides).overrideAttrs (old: rec {
            inherit ffversion;
            version = ffversion;
            name = "firefox-nightly-unwrapped-${ffversion}";
            src = gecko-dev;
            patches = [
              ./include-prenv-before-system-dir.patch
            ]
            ++ (pkgs.lib.take 1 old.patches)
            ++ [
              ./no-buildconfig-ffx90.patch
            ];
            debugBuild = true;
            meta = old.meta // {
              mainProgram = "firefox";
            };
          });
      };
    };
}
