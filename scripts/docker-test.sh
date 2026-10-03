#!/bin/sh
# Build and test inside the official Swift image (Linux).
cd "$(dirname "$0")/.." && exec docker run --rm -v "$PWD":/src -v introspection-swift-build:/src/.build -w /src swift:6.1-noble swift test "$@"
