#!/usr/bin/env bash
# Pins the Dockerfile to Sure's latest stable release.
#
# Sure publishes alpha pre-releases every few days; GitHub's "latest release"
# skips them, so the template only follows stable releases. The update workflow
# runs this once a day.
#
# Prints a markdown summary of the change; prints nothing if nothing changed.
set -euo pipefail

DOCKERFILE="$(dirname "$0")/../Dockerfile"
REPO=we-promise/sure

old="$(sed -n 's/^ARG SURE_VERSION=//p' "$DOCKERFILE")"
auth=()
[ -n "${GH_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GH_TOKEN")
tag="$(curl -fsSL ${auth[@]+"${auth[@]}"} "https://api.github.com/repos/$REPO/releases/latest" \
  | sed -n 's/^  "tag_name": "\(.*\)",$/\1/p')"
new="${tag#v}"

[[ "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || { echo "Could not read the latest release of $REPO" >&2; exit 1; }
[ "$old" = "$new" ] && exit 0
docker manifest inspect "ghcr.io/$REPO:$new" >/dev/null || { echo "The image ghcr.io/$REPO:$new does not exist yet" >&2; exit 1; }

sed -i.bak "s/^ARG SURE_VERSION=.*/ARG SURE_VERSION=$new/" "$DOCKERFILE" && rm -f "$DOCKERFILE.bak"
printf -- '- Sure: `%s` → `%s` ([release notes](https://github.com/%s/releases/tag/%s))\n' "$old" "$new" "$REPO" "$tag"
