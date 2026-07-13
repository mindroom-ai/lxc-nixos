#!/usr/bin/env bash
set -euo pipefail

# Bump the pins in hosts/mindroom/constants.nix to the latest upstream state:
#
#   mindroomRev                        <- mindroom-ai/mindroom       branch main
#   cinnyRev                           <- mindroom-ai/mindroom-chat branch dev
#   tuwunelVersion/tuwunelArchiveHash  <- latest mindroom-tuwunel GitHub release
#
# Run daily by .github/workflows/update-pins.yml; also safe to run by hand
# from any machine with git, curl, jq, and nix. Prints a diffstat; changes
# nothing when everything is already current.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
constants="$repo_root/hosts/mindroom/constants.nix"

for cmd in git curl jq nix; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

replace() {
  local key="$1" value="$2"
  # The value is interpolated into a sed expression below; refuse anything
  # outside the charset of git SHAs, release tags, and SRI hashes so a weird
  # upstream value fails loudly instead of corrupting constants.nix.
  case "$value" in
    *[!A-Za-z0-9._/+=-]* | "")
      echo "Refusing to write suspicious value for $key: $value" >&2
      exit 1
      ;;
  esac
  if ! grep -q "^  $key = \"" "$constants"; then
    echo "Key not found in constants.nix: $key" >&2
    exit 1
  fi
  # sed -i.bak (no space) works with both GNU and BSD sed.
  sed -i.bak "s|^  $key = \".*\";|  $key = \"$value\";|" "$constants"
  rm -f "$constants.bak"
}

branch_head() {
  local repo="$1" branch="$2" sha
  sha="$(git ls-remote "https://github.com/mindroom-ai/$repo.git" "refs/heads/$branch" | awk '{print $1}')"
  if [ -z "$sha" ]; then
    echo "Could not resolve $repo@$branch" >&2
    exit 1
  fi
  echo "$sha"
}

replace mindroomRev "$(branch_head mindroom main)"
replace cinnyRev "$(branch_head mindroom-chat dev)"

auth=()
if [ -n "${GH_TOKEN:-}" ]; then
  auth=(-H "Authorization: Bearer $GH_TOKEN")
elif [ -n "${GITHUB_TOKEN:-}" ]; then
  auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi
# ${auth[@]+...} keeps the empty-array expansion safe under set -u on
# bash < 4.4 (e.g. the stock macOS bash).
latest_tag="$(curl -fsSL ${auth[@]+"${auth[@]}"} \
  https://api.github.com/repos/mindroom-ai/mindroom-tuwunel/releases/latest | jq -r .tag_name)"
if [ -z "$latest_tag" ] || [ "$latest_tag" = "null" ]; then
  echo "Could not resolve the latest mindroom-tuwunel release" >&2
  exit 1
fi
# Validate before the tag is interpolated into the download URL below.
case "$latest_tag" in
  *[!A-Za-z0-9._-]*)
    echo "Unexpected characters in release tag: $latest_tag" >&2
    exit 1
    ;;
esac

current_tag="$(sed -n 's|^  tuwunelVersion = "\(.*\)";|\1|p' "$constants")"
if [ "$latest_tag" != "$current_tag" ]; then
  url="https://github.com/mindroom-ai/mindroom-tuwunel/releases/download/$latest_tag/tuwunel-$latest_tag-linux-x86_64.tar.gz"
  echo "Tuwunel $current_tag -> $latest_tag; prefetching $url"
  hash="$(nix --extra-experimental-features nix-command store prefetch-file --json "$url" | jq -r .hash)"
  replace tuwunelVersion "$latest_tag"
  replace tuwunelArchiveHash "$hash"
fi

git -C "$repo_root" --no-pager diff --stat -- "$constants"
