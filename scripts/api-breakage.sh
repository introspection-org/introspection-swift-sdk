#!/bin/sh
# Fails when the public API of the library products breaks against a baseline ref.
# Usage: scripts/api-breakage.sh [<baseline ref>]   (default: the latest vX.Y.Z tag)
# All traits are enabled so the trait-gated IntrospectionTelemetry API is compared too.
set -eu
cd "$(dirname "$0")/.."
baseline="${1:-$(git describe --tags --abbrev=0 --match 'v[0-9]*')}"
echo "Comparing the public API with $baseline ($(git rev-parse --short "$baseline^{commit}"))"
swift package --enable-all-traits diagnose-api-breaking-changes "$baseline" \
    --products IntrospectionSDK IntrospectionTelemetry
