#!/bin/sh
# Fails when the public API of the library products breaks against a baseline ref.
# Usage: scripts/api-breakage.sh [<baseline ref>]   (default: the latest vX.Y.Z tag)
# All traits are enabled so the trait-gated IntrospectionTelemetry API is compared too.
# Exits 0 when nothing broke, 1 when the API broke, and 3 when the comparison crashed and
# so never finished, which says nothing about the API.
set -eu
cd "$(dirname "$0")/.."
baseline="${1:-$(git describe --tags --abbrev=0 --match 'v[0-9]*')}"
echo "Comparing the public API with $baseline ($(git rev-parse --short "$baseline^{commit}"))"
status=0
swift package --enable-all-traits diagnose-api-breaking-changes "$baseline" \
    --products IntrospectionSDK IntrospectionTelemetry || status=$?
if [ "$status" -gt 128 ]; then
    echo "diagnose-api-breaking-changes crashed (signal $((status - 128))), so the API was not compared." >&2
    exit 3
fi
exit "$status"
