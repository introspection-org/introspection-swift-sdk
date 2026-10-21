#!/bin/sh
# Duplicate-code gate: jscpd over Sources with the settings in .jscpd.json, failing on any clone.
# Node.js and jscpd come from mise, at the versions locked in mise.lock.
set -eu
cd "$(dirname "$0")/.."
if ! command -v mise >/dev/null 2>&1; then
    echo "error: mise is not installed; run \`brew install mise\`, then \`mise install\`" >&2
    exit 1
fi
exec mise exec -- jscpd --config .jscpd.json "$@"
