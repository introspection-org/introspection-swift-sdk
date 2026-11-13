#!/bin/sh
# Fails when the public API of the library products breaks against a baseline ref.
# Usage: scripts/api-breakage.sh [<baseline ref>]   (default: the latest vX.Y.Z tag)
# All traits are enabled so the trait-gated IntrospectionTelemetry API is compared too.
# Swift Build, because the native build system's comparison crashes on macOS with
# swift-system 1.9.0 in the graph (https://github.com/swiftlang/swift-package-manager/issues/10824).
set -eu
cd "$(dirname "$0")/.."
baseline="${1:-$(git describe --tags --abbrev=0 --match 'v[0-9]*')}"
echo "Comparing the public API with $baseline ($(git rev-parse --short "$baseline^{commit}"))"
swift package --build-system swiftbuild --enable-all-traits diagnose-api-breaking-changes "$baseline" \
    --products IntrospectionSDK IntrospectionTelemetry
