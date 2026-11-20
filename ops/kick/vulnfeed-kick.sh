#!/usr/bin/env bash
# The maintainers' scheduler for the bundle publisher (see README.md here).
# Run hourly by vulnfeed-kick.timer: dispatches publish.yml when a release is
# due and none is queued, then starts the feed watch, which raises or clears
# the "feed-stale" issue. The token is read from a file and never printed.
set -euo pipefail
TOKEN_FILE="${VULNFEED_KICK_TOKEN_FILE:-/etc/vulnfeed-kick/token}"
export REPO="${VULNFEED_KICK_REPO:-openctemio/vulnfeed-bundles}"
GH_TOKEN="$(cat "$TOKEN_FILE")"
export GH_TOKEN
here="$(dirname "$(readlink -f "$0")")"
bash "$here/feed-health.sh" kick
gh workflow run watch.yml --repo "$REPO" --ref main
