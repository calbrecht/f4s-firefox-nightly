{
  description = "Firefox nightly build.";

  inputs = {
    gecko-dev = {
      url = github:mozilla/gecko-dev?rev=410bf344edc331550a31bf9a6e2a42f08846dc35;
      flake = false;
    };
    nixpkgs.url = github:nixos/nixpkgs?rev=a460b167f4ef3646341a8dc59195e5bac945ea77;
  };

  outputs = { self, nixpkgs, gecko-dev }:
    let
      ffversion = "86.0a1-20210102215130";

      pkgs = import nixpkgs { system = "x86_64-linux"; };

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
      packages.x86_64-linux.firefox-nightly-unwrapped =
        (pkgs.firefox-unwrapped.override overrides).overrideAttrs (old: rec {
          inherit ffversion;
          version = ffversion;
          name = "firefox-nightly-unwrapped-${ffversion}";
          src = gecko-dev;
          patches = [
            ./include-prenv-before-system-dir.patch
          ] ++ (pkgs.lib.take 2 old.patches);
        });

      defaultPackage.x86_64-linux = self.packages.x86_64-linux.firefox-nightly-unwrapped;
    };
}
