{
  description = "Firefox nightly Nix flake.";

  inputs = {
    gecko-dev = {
      url = github:mozilla/gecko-dev/385616091160f77e981ad760e788cf8b01341153;
      flake = false;
    };
    nixpkgs.url = github:nixos/nixpkgs/nixos-unstable;
  };

  outputs = { self, nixpkgs, gecko-dev }:
    let
      ffversion = "86.0a1-20210106155127";

      system = "x86_64-linux";

      pkgs = nixpkgs.legacyPackages."${system}";

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
    {
      apps."${system}" = {
        firefox-nightly = {
          type = "app";
          program = self.packages."${system}".firefox-nightly + /bin/firefox;
        };
        firefox-wayland-nightly = {
          type = "app";
          program = self.packages."${system}".firefox-wayland-nightly + /bin/firefox;
        };
      };

      defaultApp."${system}" = self.apps."${system}".firefox-nightly;

      packages."${system}" = self.overlay self.packages."${system}" pkgs;

      defaultPackage."${system}" = self.packages."${system}".firefox-nightly-unwrapped;

      overlay = final: prev: {
        firefox-nightly = prev.wrapFirefox final.firefox-nightly-unwrapped {
          version = ffversion;
          pname = "firefox-nightly";
        };
        firefox-wayland-nightly = prev.wrapFirefox final.firefox-nightly-unwrapped {
          version = ffversion;
          pname = "firefox-wayland-nightly";
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
            ] ++ (pkgs.lib.take 2 old.patches);
          });
      };
    };
}
