#!/usr/bin/env bash
# Tell #main-build-alerts when the API contract state changes: clean to drift, or
# drift to clean. A drift that stays drift stays quiet, so the channel hears each
# drift once. With no state yet, the first drift found posts.
#
# The post follows introspection-sre's change/gates/main-status.sh: a {text} JSON
# curled to the webhook, and an empty webhook prints the message instead. The
# last posted state lives in STATE_DIR/last-posted, which the workflow carries
# between runs; it is written only after a real post.
#
# env:
#   REPORT             the report APIContractTests wrote
#   STATE_DIR          holds last-posted between runs
#   RUN_URL            the run link in the message
#   SLACK_WEBHOOK_URL  empty prints the message instead of posting it
#   GITHUB_OUTPUT      optional; receives posted=true|false
set -euo pipefail

: "${REPORT:?}" "${STATE_DIR:?}" "${RUN_URL:?}"
output="${GITHUB_OUTPUT:-/dev/null}"

state=clean
case "$(head -n 1 "${REPORT}")" in
  "API contract: drift:"*) state=drift ;;
  "API contract: clean:"*) ;;
  *) echo "::error::Unexpected contract report: $(head -n 1 "${REPORT}")" >&2; exit 2 ;;
esac
previous="$(cat "${STATE_DIR}/last-posted" 2>/dev/null || true)"
echo "state=${state} last posted=${previous:-unknown}"

if [ "${state}" = drift ] && [ "${previous}" != drift ]; then
  # The first lines of the report that fit: a message much past a few thousand
  # characters is unreadable in the channel, and the job summary has the rest.
  drift="$(awk '{ if (used + length($0) > 3500) { rest++; next } print; used += length($0) + 1 }
    END { if (rest) printf "… %d more lines, in the job summary\n", rest }' "${REPORT}")"
  message="🚨 API drift: introspection-swift-sdk is out of step with the API reference on staging"$'\n'"${RUN_URL}"$'\n```\n'"${drift}"$'\n```'
elif [ "${state}" = clean ] && [ "${previous}" = drift ]; then
  message="✅ API drift cleared: introspection-swift-sdk matches the API reference on staging again"$'\n'"${RUN_URL}"
else
  echo "No state change; staying quiet."
  echo "posted=false" >>"${output}"
  exit 0
fi
# Slack reads & < > as control characters, so they travel as entities.
message="${message//&/&amp;}"
message="${message//</&lt;}"
message="${message//>/&gt;}"

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
