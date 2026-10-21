#!/bin/sh
# SwiftLint complexity and size limits (.swiftlint.yml), exactly as CI runs them.
# The SwiftLint version is pinned in .mise.toml and checksum-locked in mise.lock.
set -eu
cd "$(dirname "$0")/.."

if ! command -v mise >/dev/null; then
    echo "mise is not installed: run 'brew install mise' (or see https://mise.jdx.dev), then 'mise install'." >&2
    exit 1
fi

exec mise exec -- swiftlint lint --strict --quiet --config .swiftlint.yml "$@"
