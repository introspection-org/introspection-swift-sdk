#!/bin/sh
# Install the repository's git hooks.
set -e
cd "$(dirname "$0")/.."
cp hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
echo "Pre-commit hook installed."
