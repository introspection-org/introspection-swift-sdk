#!/bin/sh
# Formatting and lint, exactly as CI runs them. `--fix` rewrites in place first.
set -eu
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--fix" ]; then
    swift format format --in-place --recursive --configuration .swift-format Package.swift Sources Tests Examples
fi
swift format lint --strict --recursive --configuration .swift-format Package.swift Sources Tests Examples
