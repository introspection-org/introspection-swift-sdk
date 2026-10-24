#!/bin/sh
# Refresh the walk's recording from the JS SDK, so every SDK replays the same server responses.
# The JS walk records it (introspection-js-sdk tests/recordings/walk_<hash>/); this copies it and
# the bootstrap beside it into Tests/recordings/walk/.
#
#   scripts/sync-walk-recording.sh                  # from introspection-js-sdk main, through gh
#   JS_SDK_REF=<branch> scripts/sync-walk-recording.sh
#   JS_SDK_DIR=../introspection-js-sdk scripts/sync-walk-recording.sh   # from a local checkout
set -eu
cd "$(dirname "$0")/.."
DEST=Tests/recordings/walk
REPO=introspection-org/introspection-js-sdk
REF="${JS_SDK_REF:-main}"
mkdir -p "$DEST"
if [ -n "${JS_SDK_DIR:-}" ]; then
    src=$(find "$JS_SDK_DIR/tests/recordings" -maxdepth 1 -type d -name 'walk_*' | head -n 1)
    [ -n "$src" ] || { echo "No tests/recordings/walk_* in $JS_SDK_DIR" >&2; exit 1; }
    cp "$src/recording.har" "$DEST/recording.har"
    cp "$JS_SDK_DIR/tests/recordings/walk/bootstrap.json" "$DEST/bootstrap.json"
else
    dir=$(gh api "repos/$REPO/contents/tests/recordings?ref=$REF" \
        --jq '.[] | select(.type == "dir" and (.name | startswith("walk_"))) | .name' | head -n 1)
    case "$dir" in
    walk_*) ;;
    *) echo "No tests/recordings/walk_* on $REPO@$REF" >&2; exit 1 ;;
    esac
    gh api -H "Accept: application/vnd.github.raw+json" \
        "repos/$REPO/contents/tests/recordings/$dir/recording.har?ref=$REF" >"$DEST/recording.har"
    gh api -H "Accept: application/vnd.github.raw+json" \
        "repos/$REPO/contents/tests/recordings/walk/bootstrap.json?ref=$REF" >"$DEST/bootstrap.json"
fi
echo "Synced $DEST from $REPO@${JS_SDK_DIR:-$REF}: $(grep -c '"startedDateTime"' "$DEST/recording.har") entries"
