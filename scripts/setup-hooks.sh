#!/bin/sh
# Install the repository's git hooks.
set -e
cd "$(dirname "$0")/.."
# In a linked worktree .git is a file; hooks live in the common git dir shared by every worktree.
hooks_dir="$(git rev-parse --git-common-dir)/hooks"
mkdir -p "$hooks_dir"
cp hooks/pre-commit "$hooks_dir/pre-commit"
chmod +x "$hooks_dir/pre-commit"
echo "Pre-commit hook installed."
