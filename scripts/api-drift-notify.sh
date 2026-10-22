#!/usr/bin/env bash
# Tell #main-build-alerts when the nightly API drift state changes: clean to
# drift, or drift to clean. A drift that stays drift stays quiet, so the channel
# hears each drift once rather than every night until someone fixes it.
#
# scripts/api-drift-report.sh builds the report; this script owns the decision
# and the post, which follow introspection-sre's change/gates/main-status.sh: a
# {text} JSON curled to the webhook, and an empty webhook prints the message
# instead.
#
# The last posted state lives in STATE_DIR/last-posted, and the workflow carries
# that directory between runs. It is written only after a real post, so a run
# without the secret never swallows the edge the first real post needs.
#
# env:
#   REPORT_DIR         the --out directory of api-drift-report.sh
#   STATE_DIR          holds last-posted between runs
#   SLACK_WEBHOOK_URL  empty prints the message instead of posting it
#   GITHUB_OUTPUT      optional; receives posted=true|false
set -euo pipefail

: "${REPORT_DIR:?}" "${STATE_DIR:?}"
output="${GITHUB_OUTPUT:-/dev/null}"

state="$(cat "${REPORT_DIR}/state")"
body="$(cat "${REPORT_DIR}/body.txt")"
previous=""
if [ -f "${STATE_DIR}/last-posted" ]; then previous="$(cat "${STATE_DIR}/last-posted")"; fi
echo "state=${state} last posted=${previous:-none}"

edge=""
if [ "${state}" = drift ] && [ "${previous}" != drift ]; then
  edge="🚨 API drift: introspection-swift-sdk is out of step with the API reference on staging"
elif [ "${state}" = clean ] && [ "${previous}" = drift ]; then
  edge="✅ API drift cleared: introspection-swift-sdk matches the API reference on staging again"
fi

if [ -z "${edge}" ]; then
  echo "No state change (${state}, last posted ${previous:-nothing}); staying quiet."
  echo "posted=false" >>"${output}"
  exit 0
fi

message="$(printf '%s\n%s' "${edge}" "${body}")"
if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
  printf 'MAIN_STATUS_SLACK_WEBHOOK_URL is empty; would have posted:\n%s\n' "${message}"
  echo "posted=false" >>"${output}"
  exit 0
fi

code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
  -X POST -H 'Content-Type: application/json' \
  -d "$(jq -n --arg t "${message}" '{text: $t}')" "${SLACK_WEBHOOK_URL}" || true)"
case "${code}" in
  2*) echo "Posted to Slack." ;;
  *)
    echo "::warning::Slack refused the alert (HTTP ${code}), so the channel did not hear it."
    echo "posted=false" >>"${output}"
    exit 1
    ;;
esac
mkdir -p "${STATE_DIR}"
echo "${state}" >"${STATE_DIR}/last-posted"
echo "posted=true" >>"${output}"
