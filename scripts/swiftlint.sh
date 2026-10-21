#!/bin/sh
# SwiftLint complexity and size limits (.swiftlint.yml), exactly as CI runs them.
# Downloads the pinned release binary into .build on first use and checks its SHA-256,
# so no Package.swift dependency reaches consumers.
set -eu
cd "$(dirname "$0")/.."

VERSION=0.65.1
case "$(uname -s)-$(uname -m)" in
    Darwin-*)
        ASSET=portable_swiftlint.zip
        SHA256=c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0
        ;;
    Linux-x86_64)
        ASSET=swiftlint_linux_amd64.zip
        SHA256=caeed6f4a679c35539ffaf124f6c4ab4a8416917f7d8796279dc52b74026059d
        ;;
    Linux-aarch64 | Linux-arm64)
        ASSET=swiftlint_linux_arm64.zip
        SHA256=9ffa52f478e6d8eb485d37d14715ffac90abc81c58f3370d598bf75be05605f8
        ;;
    *)
        echo "No SwiftLint $VERSION binary for $(uname -s)-$(uname -m)." >&2
        exit 1
        ;;
esac

DIR=.build/swiftlint-$VERSION
if [ ! -x "$DIR/swiftlint" ]; then
    mkdir -p "$DIR"
    url=https://github.com/realm/SwiftLint/releases/download/$VERSION/$ASSET
    curl -fsSL -o "$DIR/$ASSET" "$url"
    if command -v sha256sum >/dev/null; then sum=$(sha256sum "$DIR/$ASSET"); else sum=$(shasum -a 256 "$DIR/$ASSET"); fi
    [ "${sum%% *}" = "$SHA256" ] || { echo "Checksum mismatch for $ASSET." >&2; rm -f "$DIR/$ASSET"; exit 1; }
    unzip -oq "$DIR/$ASSET" -d "$DIR"
    # The Linux archive also ships a fully static build, which needs no Swift runtime.
    [ ! -f "$DIR/swiftlint-static" ] || mv "$DIR/swiftlint-static" "$DIR/swiftlint"
    chmod +x "$DIR/swiftlint"
fi

"$DIR/swiftlint" lint --strict --quiet --config .swiftlint.yml "$@"
