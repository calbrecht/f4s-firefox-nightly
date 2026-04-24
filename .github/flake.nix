{
  description = "Match mozilla-central hg revisions with mozilla-firefox git revisions.";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      buildhub_query = ''
        {
          "sort": [{ "build.date": "desc" }],
          "size": 1,
          "query": { "bool": { "must": [
            { "term": { "source.tree": "mozilla-central" }},
            { "term": { "source.product": "firefox" }},
            { "term": { "target.channel": "nightly" }},
            { "term": { "target.platform": "linux-x86_64" }}
          ]}}
        }
      '';

      jq_extract_from_buildhub = ''
        .hits.hits[]._source | {
          version: ([.target.version, .build.id] | join("-")),
          hg_rev: .source.revision
        }
      '';

      jq_extract_from_github = ''
        [.[] | {
          sha,
          desc: .commit.message,
          date: .commit.author.date
        }]
      '';

      jq_git_rev = ''
        .git_commit | if type == "null" then error("empty") else . end
      '';

      jq_to_declare = ''
        to_entries | .[] | [.key, .value] | join("=")
      '';
    in
    {
      packages."${system}" = {

        fetch-buildhub = pkgs.writeScriptBin "fetch-buildhub" ''
          #!${pkgs.stdenv.shell}
          set -xeo pipefail

          : Fetching latest nightly info from buildhub.
          ${pkgs.curl}/bin/curl -s -X POST -d '${buildhub_query}' \
            https://buildhub.moz.tools/api/search | \
            ${pkgs.jq}/bin/jq '${jq_extract_from_buildhub}'
        '';

        fetch-github = pkgs.writeScriptBin "fetch-github" ''
          #!${pkgs.stdenv.shell}
          set -xeo pipefail

          : Fetching latest commits from github.
          ${pkgs.curl}/bin/curl -s -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/mozilla-firefox/firefox/commits?per_page=100" | \
            ${pkgs.jq}/bin/jq '${jq_extract_from_github}'
        '';

        fetch-changeset = pkgs.writeScriptBin "fetch-changeset" ''
          #!${pkgs.stdenv.shell}
          set -xeu

          : Fetching changeset $1 from mozilla-central.
          ${pkgs.curl}/bin/curl -L -s "https://hg.mozilla.org/mozilla-central/json-rev/$1"
        '';

        build-release-info = pkgs.writeScriptBin "build-release-info" ''
          #!${pkgs.stdenv.shell}
          set -xeuo pipefail

          version=
          hg_rev=
          git_rev=

          declare $(${self.packages."${system}".fetch-buildhub}/bin/fetch-buildhub | \
            ${pkgs.jq}/bin/jq --raw-output '${jq_to_declare}')

          test -z $(${pkgs.git}/bin/git tag -l $version) || {
            : Version $version exists, exiting.
            exit 0
          }

          : Matching $hg_rev to git revision.
          git_rev=$(${pkgs.jq}/bin/jq --raw-output '${jq_git_rev}' \
            <(${self.packages."${system}".fetch-changeset}/bin/fetch-changeset $hg_rev))

          export version hg_rev git_rev
        '';

        update-flake = pkgs.writeScriptBin "update-flake" ''
          #!${pkgs.stdenv.shell}
          set -xeu

          test -z $(${pkgs.git}/bin/git tag -l $version) || {
            : Version $version exists, exiting.
            exit 0
          }

          sed -i 's/\(mozilla-firefox\/firefox\)\/.*;/\1\/'$git_rev'";/' flake.nix
          sed -i 's/\(ffversion =\) ".*"/\1 "'$version'"/' flake.nix

          ${pkgs.nixFlakes}/bin/nix flake update
        '';

        commit-and-push = pkgs.writeScriptBin "commit-and-push" ''
          #!${pkgs.stdenv.shell}
          set -xeu

          user_name=''${git_user_name:-$(git config user.name)}
          user_mail=''${git_user_mail:-$(git config user.email)}

          test -z $(${pkgs.git}/bin/git tag -l $version) || {
            : Version $version exists, exiting.
            exit 0
          }

          ${pkgs.git}/bin/git config user.name "$user_name"
          ${pkgs.git}/bin/git config user.email "$user_mail"

          ${pkgs.git}/bin/git add flake.nix >&2
          ${pkgs.git}/bin/git add flake.lock >&2

          ${pkgs.git}/bin/git commit -m "nightly $version

            hg: $hg_rev
            git: $git_rev" >&2

          ${pkgs.git}/bin/git push >&2

          ${pkgs.git}/bin/git tag $version >&2
          ${pkgs.git}/bin/git push --tags >&2
        '';

        auto-update = pkgs.writeScriptBin "auto-update" ''
          #!${pkgs.stdenv.shell}
          set -xeu

          . ${self.packages."${system}".build-release-info}/bin/build-release-info && \
          . ${self.packages."${system}".update-flake}/bin/update-flake && \
          . ${self.packages."${system}".commit-and-push}/bin/commit-and-push || \
          true
        '';

        build-firefox-wayland-nightly = pkgs.writeScriptBin "build-firefox-wayland-nightly"
        ''
          #!${pkgs.stdenv.shell}
          set -xeu

          ${pkgs.nixFlakes}/bin/nix build ./#firefox-wayland-nightly
        '';
      };
    };
}
