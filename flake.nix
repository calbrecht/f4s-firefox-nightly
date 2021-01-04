{
  description = "Firefox nightly Nix flake.";

  inputs = {
    gecko-dev = {
      url = github:mozilla/gecko-dev/8eec586c99c5198ba004a116b591e8afb1902064;
      flake = false;
    };
    nixpkgs.url = github:nixos/nixpkgs/nixpkgs-unstable;
  };

  outputs = { self, nixpkgs, gecko-dev }:
    let
      ffversion = "86.0a1-20210103213448";

      system = "x86_64-linux";

      pkgs = import nixpkgs { inherit system; };

      nss_version_prefix = "#define NSS_VERSION";
      nss_version = with pkgs.lib; with builtins; toString
        (match "${nss_version_prefix} .([0-9.]+).*"
          (toString (filter (hasPrefix nss_version_prefix)
            (splitString "\n" (readFile (gecko-dev + /security/nss/lib/nss/nss.h))))));

      nss = pkgs.nss.overrideAttrs (old: {
        src = gecko-dev + /security;
        version = nss_version;
      });

      overrides = { } //
        # https://wiki.mozilla.org/NSS:Release_Versions
        (pkgs.lib.optionalAttrs (pkgs.nss.version != nss_version) { inherit nss; }) //
        {
          rust-cbindgen = pkgs.rust-cbindgen.overrideAttrs (old: rec {
            name = "rust-cbindgen-${version}";
            version = "0.16.0";

            src = pkgs.fetchFromGitHub {
              owner = "eqrion";
              repo = "cbindgen";
              rev = "v${version}";
              sha256 = "sha256-RDqe97smZ4QPFlV4J8eV1ZHOlPKMzUow6/oNuIWgZ90=";
            };

            cargoDeps = old.cargoDeps.overrideAttrs (pkgs.lib.const {
              name = "${name}-vendor.tar.gz";
              inherit src;
              outputHash = "sha256-MdrXJ/nGxJ1oOHolc599Uee1EWn1iybUCfnc98BfjiE=";
            });

            doCheck = false;
          });
        };
    in
    with self.packages."${system}"; {

      apps."${system}" = {
        firefox-nightly = {
          type = "app";
          program = firefox-nightly + /bin/firefox;
        };
        firefox-wayland-nightly = {
          type = "app";
          program = firefox-wayland-nightly + /bin/firefox;
        };
      };

      defaultApp."${system}" = self.apps."${system}".firefox-nightly;

      packages."${system}" = {
        firefox-nightly = pkgs.wrapFirefox firefox-nightly-unwrapped {
          version = ffversion;
          pname = "firefox-nightly";
        };
        firefox-wayland-nightly = pkgs.wrapFirefox firefox-nightly-unwrapped {
          version = ffversion;
          pname = "firefox-wayland-nightly";
          forceWayland = true;
        };
        firefox-nightly-unwrapped =
          (pkgs.firefox-unwrapped.override overrides).overrideAttrs (old: rec {
            inherit ffversion;
            version = ffversion;
            name = "firefox-nightly-unwrapped-${ffversion}";
            src = gecko-dev;
            patches = [
              ./include-prenv-before-system-dir.patch
            ] ++ (pkgs.lib.take 2 old.patches);
          });
      };

      defaultPackage."${system}" = firefox-nightly-unwrapped;

      overlay = final: prev: {
        inherit (self.packages."${system}")
          firefox-nightly firefox-wayland-nightly firefox-nightly-unwrapped;
      };
    };
}
