#!/usr/bin/env bash
# Move an issue's item in the "VYNOR Development" project to another Status.
#
# Usage: project-status.sh [--forward] <issue-number> <status>
#   <status>   stage prefix ("08") or full option name ("08 Post-Merge Verification")
#   --forward  leave the item alone when it is already at or past <status>
#
# Needs gh authenticated with the `project` and `repo` scopes (GH_TOKEN in Actions).
set -euo pipefail

OWNER=Alkanni
REPO=vynor-omnichannel-crm
PROJECT_NUMBER=1

die() {
  echo "project-status: $*" >&2
  exit 1
}

forward=false
if [[ ${1-} == --forward ]]; then
  forward=true
  shift
fi
[[ $# -eq 2 ]] || die "usage: project-status.sh [--forward] <issue-number> <status>"
issue=$1
status=$2
[[ $issue =~ ^[1-9][0-9]*$ ]] || die "invalid issue number: $issue"

data=$(gh api graphql -f owner="$OWNER" -f repo="$REPO" -F number="$PROJECT_NUMBER" -F issue="$issue" -f query='
  query($owner: String!, $repo: String!, $number: Int!, $issue: Int!) {
    user(login: $owner) {
      projectV2(number: $number) {
        id
        field(name: "Status") { ... on ProjectV2SingleSelectField { id options { id name } } }
      }
    }
    repository(owner: $owner, name: $repo) {
      issue(number: $issue) {
        projectItems(first: 20) {
          nodes {
            id
            project { id }
            status: fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
          }
        }
      }
    }
  }')

project=$(jq -c '.data.user.projectV2' <<<"$data")
option=$(jq -c --arg s "$status" '[.field.options[] | select(.name == $s or (.name | startswith($s + " ")))]' <<<"$project")
[[ $(jq length <<<"$option") -eq 1 ]] || die "unknown status: $status"
target=$(jq -r '.[0].name' <<<"$option")

item=$(jq -c --argjson p "$project" '.data.repository.issue.projectItems.nodes | map(select(.project.id == $p.id)) | first // empty' <<<"$data")
[[ -n $item ]] || die "issue #$issue is not in the project"
current=$(jq -r '.status.name // ""' <<<"$item")

if $forward && [[ -n $current && ! ${current%% *} < ${target%% *} ]]; then
  echo "#$issue: $current (unchanged, already at or past $target)"
  exit 0
fi

gh project item-edit --id "$(jq -r .id <<<"$item")" --project-id "$(jq -r .id <<<"$project")" \
  --field-id "$(jq -r .field.id <<<"$project")" --single-select-option-id "$(jq -r '.[0].id' <<<"$option")" >/dev/null
echo "#$issue: ${current:-(none)} → $target"
