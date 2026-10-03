#!/bin/sh
# Run the tests with coverage and fail when line coverage drops below the floor.
# The floor is a do-not-regress gate: raise it as coverage grows, and never lower
# it without saying why in the pull request.
set -eu
cd "$(dirname "$0")/.."
THRESHOLD="${COVERAGE_THRESHOLD:-75}"

swift test --enable-code-coverage "$@"

BIN_DIR=$(swift build --show-bin-path)
PROFILE="$BIN_DIR/codecov/default.profdata"
BINARY="$BIN_DIR/IntrospectionSDKPackageTests.xctest"
if [ -f "$BINARY/Contents/MacOS/IntrospectionSDKPackageTests" ]; then
    BINARY="$BINARY/Contents/MacOS/IntrospectionSDKPackageTests"
fi
if command -v xcrun >/dev/null 2>&1; then LLVM_COV="xcrun llvm-cov"; else LLVM_COV="llvm-cov"; fi

$LLVM_COV report -instr-profile "$PROFILE" "$BINARY" -ignore-filename-regex='Tests/|\.build/' | tee coverage.txt
LINES=$(awk '/^TOTAL/ { gsub("%", "", $10); print $10 }' coverage.txt)
awk -v lines="$LINES" -v floor="$THRESHOLD" 'BEGIN {
    if (lines + 0 < floor + 0) { printf "Line coverage %.2f%% is below the %s%% floor\n", lines, floor; exit 1 }
    printf "Line coverage %.2f%% (floor %s%%)\n", lines, floor
}'
