#!/usr/bin/env bash
# Build the nightly API drift report that .github/workflows/api-contract.yml posts
# to #main-build-alerts. Two reports, because they answer different questions:
#
# - SDK drift: where Sources disagree with the API reference, from the contract
#   check (Tests/IntrospectionSDKTests/APIContractTests.swift), passed in as the
#   report file it wrote.
# - Reference changelog: what changed in the API since the saved copies in
#   api-reference/ were taken, from oasdiff.
#
# Either one being non-empty is drift: the SDK needs fixing, or the saved copies
# are behind even when the SDK happens to match.
#
# Writes to --out:
#   state       drift | clean
#   body.txt    the Slack message below its headline: summary, run link, and both
#               reports trimmed to fit
#   summary.md  both reports in full, for the job summary
#
# Exits 0 when the report was built (drift or clean) and 2 when it could not be,
# for example when staging did not answer or the check wrote no report: an outage
# is not drift, and must not post or change the notify state.
#
# Run: scripts/api-drift-report.sh --check-report FILE --out DIR [--run-url URL]
# env: OASDIFF (default: oasdiff on PATH), CONTROLPLANE_URL, DATAPLANE_URL
set -euo pipefail
cd "$(dirname "$0")/.."

out=""
check_report=""
run_url="(local run)"
while [ $# -gt 0 ]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --check-report) check_report="$2"; shift 2 ;;
    --run-url) run_url="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ -z "${out}" ] || [ -z "${check_report}" ]; then
  echo "usage: api-drift-report.sh --check-report FILE --out DIR [--run-url URL]" >&2
  exit 2
fi

oasdiff="${OASDIFF:-oasdiff}"
live() {
  case "$1" in
    controlplane) echo "${CONTROLPLANE_URL:-https://api.staging.introspection.dev/openapi/controlplane.json}" ;;
    dataplane) echo "${DATAPLANE_URL:-https://api.staging.introspection.dev/openapi/dataplane.json}" ;;
  esac
}
# Characters each report may take in the Slack message. Slack truncates at 40,000,
# but a message much past 10,000 is unreadable in the channel; the job summary has
# the rest.
drift_budget=3500
plane_budget=2500

if [ ! -s "${check_report}" ]; then
  echo "::error::The contract check wrote no report (${check_report}); see the check job's log." >&2
  exit 2
fi
check_text="$(cat "${check_report}")"
check_headline="$(head -n 1 "${check_report}")"
check_drift=false
case "${check_headline}" in
  "API contract: drift:"*) check_drift=true ;;
  "API contract: clean:"*) ;;
  *) echo "::error::Unexpected contract check report: ${check_headline}" >&2; exit 2 ;;
esac

# One plane's changes from the saved copy to staging, one line per change, most
# severe first: oasdiff's level 3 is breaking, 2 potentially breaking.
changelog() {
  local plane="$1" json
  if ! json="$("${oasdiff}" changelog "api-reference/${plane}.json" "$(live "${plane}")" --format json)"; then
    echo "::error::oasdiff could not compare api-reference/${plane}.json with $(live "${plane}")" >&2
    return 1
  fi
  jq -r --arg plane "${plane}" '
    (. // []) as $changes
    | ($changes | map(select(.level == 3)) | length) as $breaking
    | ($changes | map(select(.level == 2)) | length) as $maybe
    | "\($plane): \($changes | length) changes, \($breaking) breaking, \($maybe) potentially breaking",
      ($changes | sort_by(-.level, .operation // "", .path // "")[]
        | "  \(if .level == 3 then "BREAKING: " elif .level == 2 then "MAYBE BREAKING: " else "" end)\(.text) — \(if .path then "\(.operation) \(.path)" else .section end)")
  ' <<<"${json}"
}

# The first lines of $1 that fit in $2 characters.
trim() {
  local text="$1" budget="$2"
  if [ "${#text}" -le "${budget}" ]; then
    printf '%s' "${text}"
    return
  fi
  awk -v budget="${budget}" '
    { if (used + length($0) + 1 > budget) { rest++; next } print; used += length($0) + 1 }
    END { printf "… %d more lines, in the job summary", rest }
  ' <<<"${text}"
}

changelogs=""
trimmed=""
headers=""
changed=false
for plane in controlplane dataplane; do
  text="$(changelog "${plane}")" || exit 2
  headers+="Reference ${text%%$'\n'*}"$'\n'
  [ "$(printf '%s\n' "${text}" | wc -l)" -gt 1 ] && changed=true
  changelogs+="${text}"$'\n\n'
  trimmed+="$(trim "${text}" "${plane_budget}")"$'\n\n'
done

state=clean
if [ "${check_drift}" = true ] || [ "${changed}" = true ]; then state=drift; fi
check_counts="${check_headline#API contract: }"
summary_lines="SDK drift: ${check_counts#*: }"$'\n'"${headers}"

mkdir -p "${out}"
echo "${state}" >"${out}/state"
if [ "${state}" = drift ]; then
  drift="$(trim "${check_text}" "${drift_budget}")"$'\n\n'"${trimmed%$'\n\n'}"
  body="${summary_lines}${run_url}"$'\n```\n'"${drift}"$'\n```'
else
  body="${run_url}"
fi
# Slack reads & < > as control characters, so they travel as entities.
body="${body//&/&amp;}"
body="${body//</&lt;}"
body="${body//>/&gt;}"
printf '%s\n' "${body}" >"${out}/body.txt"
{
  echo "## API drift: ${state}"
  echo
  printf '%s' "${summary_lines}" | sed 's/^/- /'
  echo
  echo "### SDK drift"
  echo
  echo '```'
  echo "${check_text}"
  echo '```'
  echo
  echo "### Reference changelog"
  echo
  echo '```'
  printf '%s' "${changelogs}"
  echo '```'
} >"${out}/summary.md"
echo "API drift: ${state}"
printf '%s' "${summary_lines}"
