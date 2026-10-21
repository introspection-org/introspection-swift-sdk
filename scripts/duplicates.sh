#!/bin/sh
# Duplicate-code gate: jscpd over Sources with the settings in .jscpd.json, failing on any clone.
# Needs Node.js (npx); the version is pinned so a jscpd release cannot change the result.
set -eu
cd "$(dirname "$0")/.."
exec npx --yes jscpd@5.4.1 --config .jscpd.json "$@"
