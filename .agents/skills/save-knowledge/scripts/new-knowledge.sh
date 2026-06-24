#!/usr/bin/env bash
#
# new-knowledge.sh
#   Deterministically generate the save path for a knowledge file.
#   - Create knowledge/ under the project root (if absent)
#   - Print a unique path knowledge/YYYY-MM-DD-<slug>.md to stdout (appends -2, -3 ... on collision)
#   - Does NOT touch INDEX (INDEX update is handled by the SKILL.md flow)
#
# Usage:
#   new-knowledge.sh "<slug>" [<project-root>]
#     <slug>          : short kebab-case slug for the filename (required)
#     <project-root>  : project root (defaults to current directory)
#
# Output:
#   Relative path of the file to create (one line). The caller writes to this path.
#
set -euo pipefail

SLUG="${1:-}"
ROOT="${2:-$(pwd)}"

if [[ -z "$SLUG" ]]; then
  echo "ERROR: slug is required. usage: new-knowledge.sh <slug> [project-root]" >&2
  exit 2
fi

# Sanitize slug: lowercase, non-alnum -> hyphen, collapse repeats, trim leading/trailing hyphens
SAFE_SLUG="$(printf '%s' "$SLUG" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/-+/-/g; s/^-//; s/-$//')"

if [[ -z "$SAFE_SLUG" ]]; then
  SAFE_SLUG="knowledge"
fi

DATE="$(date +%F)"        # YYYY-MM-DD

KDIR="$ROOT/knowledge"

mkdir -p "$KDIR"

BASE="${DATE}-${SAFE_SLUG}"
TARGET="$KDIR/${BASE}.md"

# Avoid filename collisions
if [[ -e "$TARGET" ]]; then
  i=2
  while [[ -e "$KDIR/${BASE}-${i}.md" ]]; do
    i=$((i + 1))
  done
  TARGET="$KDIR/${BASE}-${i}.md"
fi

# Return a path relative to ROOT
printf '%s\n' "knowledge/$(basename "$TARGET")"
