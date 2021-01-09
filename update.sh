#!/usr/bin/env nix-shell
#!nix-shell -i bash -p cacert curl git gnupg jq nixFlakes --pure

user_agent="Collect nightly Firefox revisions for mapping to github source archives (github.com/calbrecht)"
buildhub_api_url=https://buildhub.moz.tools/api
hg_changeset_url=https://hg.mozilla.org/mozilla-central/rev
github_commits_url=https://api.github.com/repos/mozilla/gecko-dev/commits

tmp=$(realpath .tmp)
cache=$(realpath .cache)
history_json=${cache}/history.json
tmp_history_json=${tmp}/history.json

hourly=$(date -Ihours)

buildhub_json=buildhub.json
github_json=github.json
hourly_buildhub_json=${cache}/${hourly}.${buildhub_json}
hourly_github_json=${cache}/${hourly}.${github_json}
state_buildhub_json=${cache}/${buildhub_json}
state_github_json=${cache}/${github_json}
tmp_buildhub_json=${tmp}/${buildhub_json}
tmp_github_json=${tmp}/${github_json}

[[ -d ${tmp} ]] || mkdir ${tmp}
[[ -d ${cache} ]] || mkdir ${cache}

jq_files_differ () {
    test $(jq --sort-keys --slurp '.[0] == .[1]' "${1}" "${2}") = false
}

read -d ¬ buildhub_query <<¬¬
{
  "sort": [{ "build.date": "asc" }],
  "size": 10,
  "query": { "bool": { "must": [
      { "term": { "source.tree": "mozilla-central" }},
      { "term": { "source.product": "firefox" }},
      { "term": { "target.channel": "nightly" }},
      { "term": { "target.platform": "linux-x86_64" }},
      { "range": { "build.date": { "gte": "now-1d/d" } }}
  ]}}
}
¬¬

test -s ${hourly_buildhub_json} || {
    echo Fetching hourly mozilla ${hourly}.
    curl -A "${user_agent}" -X POST ${buildhub_api_url}/search -d "${buildhub_query}" \
         -o ${hourly_buildhub_json}
}

read -d ¬ jq_sort <<¬¬
  unique_by(.hg_rev) |
  sort_by(.version)
¬¬

read -d ¬ jq_extract_from_buildhub <<¬¬
[
  .hits.hits[]._source | {
    version: ([.target.version, .build.id] | join("-")),
    hg_rev: .source.revision
  }
] | ${jq_sort}
¬¬

echo Extracting temporary state from hourly mozilla.
jq --sort-keys "${jq_extract_from_buildhub}" ${hourly_buildhub_json} 1> ${tmp_buildhub_json}

jq_files_differ ${tmp_buildhub_json} ${state_buildhub_json} && {
    echo New state from buildhub.
    cp ${tmp_buildhub_json} ${state_buildhub_json}
} || {
    echo Nothing changed from buildhub.
}

test -s ${hourly_github_json} || {
    echo Fetching hourly github ${hourly}.
    curl -H "Accept: application/vnd.github.v3+json" "${github_commits_url}?per_page=100" \
         -o ${hourly_github_json}
}

read -d ¬ jq_extract_from_github <<¬¬
[.[] | {
  sha,
  desc: .commit.message,
  date: .commit.author.date
}] |
  sort_by(.sha)
¬¬

echo Extracting temporary state from hourly github.
jq --sort-keys "${jq_extract_from_github}" ${hourly_github_json} 1> ${tmp_github_json}

jq_files_differ ${tmp_github_json} ${state_github_json} && {
    echo New state from github.
    cp ${tmp_github_json} ${state_github_json}
} || {
    echo Nothing changed from github.
}

read -d ¬ jq_git_rev <<'¬¬'
# TODO there are same commits with different parents. for now just take the first one
[.[0] as {$desc, $date} |
  ($desc | rtrimstr("\\n")) as $desc |
  ($date | $date[0] | gmtime | strftime("%Y-%m-%dT%H:%M:%SZ")) as $date |
.[1][] | select(.desc == $desc and .date == $date) |
  .sha] |
  if length > 1 then debug else . end |
  .[0] |
  if type == "null" then error("empty") else . end
¬¬

read -d ¬ jq_merge <<¬¬
.[0] + .[1] |
  ${jq_sort} |
  .[]
¬¬

while read line ; do
    version=
    hg_rev=
    git_rev=

    declare $(echo $line | jq --raw-output 'to_entries | .[] | [.key, .value] | join("=")')

    test -z ${git_rev} && {
        changeset=${cache}/${hg_rev}.changeset.json

        test -s ${changeset} || {
            echo Fetching changeset ${hg_rev}. >&2
            curl -A "${user_agent}" "${hg_changeset_url}/${hg_rev}?style=json" -o ${changeset}
        }

        echo Searching git_rev for hg: ${hg_rev}. >&2
        set -x
        git_rev=$(jq --slurp --raw-output "${jq_git_rev}" ${changeset} ${state_github_json}) || {
            echo Unable to find git_rev, exiting. >&2
            exit 1
        }
    }

    test -z $(git tag -l ${version}) && {
        sed -i 's/\(gecko-dev\)\/.*;/\1\/'${git_rev}';/' flake.nix
        sed -i 's/\(ffversion =\) ".*"/\1 "'${version}'"/' flake.nix

        git add flake.nix >&2
        nix flake update --recreate-lock-file
        git add flake.lock >&2

        git commit -m "nightly ${version}

hg: ${hg_rev}
git: ${git_rev}" >&2

        git tag ${version} >&2
    }

    jq --null-input --arg version ${version} --arg hg_rev ${hg_rev} --arg git_rev ${git_rev} '
       {$version, $hg_rev, $git_rev}
    '

done 1> >(jq --slurp "${jq_sort}" > ${tmp_history_json}) \
     < <(jq --slurp --compact-output "${jq_merge}" ${history_json} ${state_buildhub_json})

wait

jq_greater_length () {
    test $(jq --slurp '(.[0] | length) > (.[1] | length)' "${1}" "${2}") = true
}

jq_files_differ ${tmp_history_json} ${history_json} && \
jq_greater_length ${tmp_history_json} ${history_json} && {
    echo New nightly.
    cp ${tmp_history_json} ${history_json}
} || {
    echo No new nightly.
}

hourly_regex='.*/[0-9T:+-]+\.[a-z]+\.json'

echo Cleanup hourly {build,git}hub.json cache.
find ${cache} -regex ${hourly_regex} -mtime 0.042
find ${cache} -regex ${hourly_regex} -mtime 0.042 -exec rm \{\} \;

echo Cleanup changeset.json cache.
find ${cache} -name '*.changeset.json' -mtime 2
find ${cache} -name '*.changeset.json' -mtime 2 -exec rm \{\} \;

echo Cleanup tmp.
rm ${tmp}/*
