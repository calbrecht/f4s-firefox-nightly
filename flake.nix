{
  description = "Nix flake for Firefox nightly.";

  nixConfig = {
    flake-registry = https://github.com/calbrecht/f4s-registry/raw/main/flake-registry.json;
  };

  inputs = {
    nixpkgs.url = flake:f4s-nixpkgs;
    gecko-dev = {
      url = github:mozilla/gecko-dev/f837285619240f496ced176161851c97be8f2eb5;
      flake = false;
    };
    nss-dev = {
      url = flake:f4s-nss;
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nspr-dev = {
      url = flake:f4s-nspr;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, gecko-dev, nss-dev, nspr-dev }:
    let
      ffversion = "98.0a1-20220203003951";

      system = "x86_64-linux";

      pkgs = nixpkgs.legacyPackages."${system}";

      overrides = {
        nss = nss-dev.legacyPackages."${system}".nss-dev;
        nspr = nspr-dev.legacyPackages."${system}".nspr-dev;

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
            "--skip bin_explicit_release_build"
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
