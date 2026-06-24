#!/usr/bin/env bash
#
# search-knowledge.sh
#   Search the project's knowledge/ folder for past trouble reports relevant to the
#   current trouble, and print a ranked list of candidate files to stdout.
#
#   Ranking: each search term is matched case-insensitively against every knowledge
#   file; a file's score is the number of *distinct* terms it matches (higher = better),
#   tie-broken by total match count. Files matching zero terms are omitted.
#
# Usage:
#   search-knowledge.sh "<term1>" ["<term2>" ...] [--root <project-root>]
#     <termN>          : search terms (error type / tech / library / keyword). At least 1.
#     --root <path>    : project root (defaults to current directory)
#
# Output (one block per matching file, best first):
#   SCORE=<distinct-terms>/<total-terms>  HITS=<total-matches>  knowledge/<file>.md
#     <matched term> | <first matching line, trimmed>
#     ...
#
# Exit codes:
#   0  matches found (or no knowledge dir / no matches — see stderr note)
#   2  usage error (no terms given)
#
set -euo pipefail

ROOT="$(pwd)"
TERMS=()

# Parse args (support --root anywhere)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT="${2:-$(pwd)}"
      shift 2
      ;;
    *)
      TERMS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#TERMS[@]} -eq 0 ]]; then
  echo "ERROR: at least one search term is required. usage: search-knowledge.sh <term> [<term> ...] [--root <path>]" >&2
  exit 2
fi

KDIR="$ROOT/knowledge"

if [[ ! -d "$KDIR" ]]; then
  echo "NO_KNOWLEDGE_DIR: $KDIR does not exist yet (nothing saved). Proceed without past knowledge." >&2
  exit 0
fi

TOTAL_TERMS=${#TERMS[@]}
FOUND_ANY=0

# Collect knowledge files (exclude INDEX.md from per-file ranking; it is a directory).
shopt -s nullglob
FILES=("$KDIR"/*.md)
shopt -u nullglob

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "NO_KNOWLEDGE_FILES: $KDIR has no .md files yet. Proceed without past knowledge." >&2
  exit 0
fi

# Build a scored, sortable line per file, then sort and print.
RESULTS=()
for f in "${FILES[@]}"; do
  base="$(basename "$f")"
  # Skip meta docs that aren't trouble reports (index / folder readme).
  [[ "$base" == "INDEX.md" || "$base" == "README.md" ]] && continue

  distinct=0
  total=0
  detail=""
  for term in "${TERMS[@]}"; do
    # Count matches for this term in this file (case-insensitive, fixed-string).
    cnt="$(grep -icF -- "$term" "$f" 2>/dev/null || true)"
    cnt="${cnt:-0}"
    if [[ "$cnt" -gt 0 ]]; then
      distinct=$((distinct + 1))
      total=$((total + cnt))
      # First matching line, trimmed for display.
      line="$(grep -im1 -F -- "$term" "$f" 2>/dev/null | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | cut -c1-120 || true)"
      # Use a sentinel (\x01) for line breaks so the whole block stays on ONE
      # sortable line; converted back to real newlines after sorting.
      detail+=$'\x01'"    ${term} | ${line}"
    fi
  done

  if [[ "$distinct" -gt 0 ]]; then
    FOUND_ANY=1
    # Sort key: zero-padded distinct, then zero-padded total (descending sort later).
    printf -v key '%03d%06d' "$distinct" "$total"
    RESULTS+=("${key}|SCORE=${distinct}/${TOTAL_TERMS}  HITS=${total}  knowledge/${base}${detail}")
  fi
done

if [[ "$FOUND_ANY" -eq 0 ]]; then
  echo "NO_MATCH: no knowledge file matched the given terms. Proceed without past knowledge (consider saving this one afterward)." >&2
  exit 0
fi

# Sort by score descending (one block per line), strip the sort key, then turn the
# \x01 sentinels back into real newlines so each file's detail stays under its header.
printf '%s\n' "${RESULTS[@]}" \
  | sort -rt '|' -k1,1 \
  | sed -E 's/^[0-9]+\|//' \
  | tr '\001' '\n'
