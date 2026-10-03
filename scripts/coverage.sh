#!/bin/sh
# Run the tests with coverage and fail when line coverage drops below the floor.
# The floor is a do-not-regress gate: raise it as coverage grows, and never lower
# it without saying why in the pull request.
set -eu
cd "$(dirname "$0")/.."
THRESHOLD="${COVERAGE_THRESHOLD:-75}"

swift test --enable-code-coverage "$@"

CODECOV_DIR=$(dirname "$(swift test --show-codecov-path "$@")")
PROFILE="$CODECOV_DIR/default.profdata"
BIN_DIR=$(dirname "$CODECOV_DIR")
# The test product's name and shape depend on the toolchain and build system: an
# `.xctest` bundle (a directory on macOS, an executable on Linux) or, with the
# Swift Build layout, a `<target>.so` / `.dylib` loaded by a test runner.
BINARY=""
for candidate in "$BIN_DIR"/*.xctest "$BIN_DIR"/*Tests.so "$BIN_DIR"/*Tests.dylib; do
    [ -e "$candidate" ] || continue
    if [ -d "$candidate" ]; then
        name=$(basename "$candidate" .xctest)
        candidate="$candidate/Contents/MacOS/$name"
    fi
    if [ -f "$candidate" ]; then
        BINARY="$candidate"
        break
    fi
done
if [ -z "$BINARY" ] || [ ! -f "$PROFILE" ]; then
    echo "No test binary or profile under $BIN_DIR (binary: '$BINARY', profile: $PROFILE)" >&2
    exit 1
fi
if command -v xcrun >/dev/null 2>&1; then LLVM_COV="xcrun llvm-cov"; else LLVM_COV="llvm-cov"; fi

$LLVM_COV report -instr-profile "$PROFILE" "$BINARY" "$PWD/Sources" | tee coverage.txt
LINES=$(awk '/^TOTAL/ { gsub("%", "", $10); print $10 }' coverage.txt)
awk -v lines="$LINES" -v floor="$THRESHOLD" 'BEGIN {
    if (lines + 0 < floor + 0) { printf "Line coverage %.2f%% is below the %s%% floor\n", lines, floor; exit 1 }
    printf "Line coverage %.2f%% (floor %s%%)\n", lines, floor
}'
