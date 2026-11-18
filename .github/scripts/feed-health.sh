#!/usr/bin/env bash
# Feed health: is the newest release recent, and did the last publish run
# succeed? Used by .github/workflows/watch.yml (and runnable by hand with a
# token that can read this repository).
#
#   feed-health.sh check      print the state, exit 0 healthy, 1 unhealthy
#   feed-health.sh kick       dispatch publish.yml when a release is due and
#                             no publish run is queued or running
#   feed-health.sh alert      open (or update) the "feed-stale" issue while
#                             unhealthy, close it when healthy
#
# Environment: GH_TOKEN, REPO (owner/name; default $GITHUB_REPOSITORY),
# STALE_AFTER_MIN (default 120), DUE_AFTER_MIN (default 55).
set -euo pipefail

REPO="${REPO:-${GITHUB_REPOSITORY:?set REPO or GITHUB_REPOSITORY}}"
STALE_AFTER_MIN="${STALE_AFTER_MIN:-120}"
DUE_AFTER_MIN="${DUE_AFTER_MIN:-55}"
LABEL="feed-stale"
TITLE="Vulnerability bundle feed is stale or failing"

now_s() { date -u +%s; }

# newest_release prints "<tag> <published_at>" of the highest v1-N release
# that is published (not a draft), or nothing.
newest_release() {
  gh release list --repo "$REPO" --limit 200 --json tagName,publishedAt,isDraft \
    --jq '[.[] | select(.isDraft | not) | select(.tagName | test("^v1-[0-9]+$"))]
          | sort_by(.tagName | ltrimstr("v1-") | tonumber) | reverse | .[0]
          | select(. != null) | "\(.tagName) \(.publishedAt)"'
}

# runs prints the recent publish runs as JSON.
runs() {
  gh run list --repo "$REPO" --workflow publish.yml --limit 20 \
    --json databaseId,status,conclusion,createdAt,event,url
}

# state sets TAG, AGE_MIN, ACTIVE (0/1), FAILED_URL ("" when the last
# finished run did not fail) and PROBLEMS (one line each).
state() {
  local rel r
  rel="$(newest_release)"
  TAG="${rel%% *}"
  if [ -z "$rel" ]; then
    TAG="(none)"
    AGE_MIN=999999
  else
    local pub="${rel#* }"
    AGE_MIN=$(( ( $(now_s) - $(date -u -d "$pub" +%s) ) / 60 ))
  fi
  r="$(runs)"
  ACTIVE="$(jq -r '[.[] | select(.status != "completed")] | if length > 0 then 1 else 0 end' <<<"$r")"
  # The last run that finished. "cancelled" is not a failure: a queued run
  # is cancelled when a newer one replaces it (concurrency group).
  FAILED_URL="$(jq -r '[.[] | select(.status == "completed" and .conclusion != "cancelled" and .conclusion != "skipped")][0]
    | select(. != null) | select(.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "startup_failure")
    | .url' <<<"$r")"
  PROBLEMS=""
  if [ "$AGE_MIN" -gt "$STALE_AFTER_MIN" ]; then
    PROBLEMS+="- The newest release ${TAG} is ${AGE_MIN} minutes old (limit ${STALE_AFTER_MIN})."$'\n'
  fi
  if [ -n "$FAILED_URL" ]; then
    PROBLEMS+="- The last publish run failed: ${FAILED_URL}"$'\n'
  fi
}

cmd_check() {
  state
  echo "newest=${TAG} age_min=${AGE_MIN} active_run=${ACTIVE} last_failed=${FAILED_URL:-no}"
  [ -z "$PROBLEMS" ] || { printf '%s' "$PROBLEMS"; return 1; }
}

cmd_kick() {
  state
  if [ "$ACTIVE" = "1" ]; then
    echo "a publish run is queued or running: nothing to do"
    return 0
  fi
  if [ "$AGE_MIN" -lt "$DUE_AFTER_MIN" ]; then
    echo "newest release ${TAG} is ${AGE_MIN} minutes old: not due"
    return 0
  fi
  echo "newest release ${TAG} is ${AGE_MIN} minutes old: dispatching publish.yml"
  # No inputs: a dispatch from a scheduler never overrides a guard.
  gh workflow run publish.yml --repo "$REPO" --ref main
}

cmd_alert() {
  state
  local open
  open="$(gh issue list --repo "$REPO" --label "$LABEL" --state open --limit 1 --json number --jq '.[0].number // empty')"
  if [ -n "$PROBLEMS" ]; then
    local body
    body="$(printf 'The feed watch found a problem at %s UTC:\n\n%s\nPlatforms keep the data they have and show it as out of date. Steps: check the last publish run, fix the cause, then dispatch publish.yml. This issue closes itself when a fresh release is out and the last run succeeded.\n' \
      "$(date -u '+%Y-%m-%d %H:%M')" "$PROBLEMS")"
    if [ -z "$open" ]; then
      gh label create "$LABEL" --repo "$REPO" --color B60205 \
        --description "The bundle feed is stale or the publisher failed" >/dev/null 2>&1 || true
      gh issue create --repo "$REPO" --title "$TITLE" --label "$LABEL" --body "$body"
    else
      # Keep the open issue current; a new failed run adds a comment so the
      # watchers are told again.
      gh issue edit "$open" --repo "$REPO" --body "$body" >/dev/null
      if [ -n "$FAILED_URL" ] && ! gh issue view "$open" --repo "$REPO" --json comments \
           --jq '.comments[].body' | grep -qF "$FAILED_URL"; then
        gh issue comment "$open" --repo "$REPO" --body "Another publish run failed: ${FAILED_URL}"
      fi
    fi
    return 1
  fi
  if [ -n "$open" ]; then
    gh issue close "$open" --repo "$REPO" \
      --comment "Recovered: newest release ${TAG} is ${AGE_MIN} minutes old and the last publish run succeeded."
  fi
  echo "healthy: newest=${TAG} age_min=${AGE_MIN}"
}

case "${1:-check}" in
  check) cmd_check ;;
  kick) cmd_kick ;;
  alert) cmd_alert ;;
  *) echo "usage: $0 check|kick|alert" >&2; exit 2 ;;
esac
