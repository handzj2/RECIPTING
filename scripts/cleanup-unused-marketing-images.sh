#!/usr/bin/env bash
# Remove marketing image files not referenced in public HTML/JS/CSS.
# Run from project root. Safe: only deletes under public/assets/marketing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
M="$ROOT/public/assets/marketing"
cd "$M"

# Build referenced set
REFS=$(mktemp)
grep -rohE '/assets/marketing/[a-zA-Z0-9_./-]+\.(jpg|jpeg|webp|avif|png)' "$ROOT/public" 2>/dev/null \
  | sed 's|.*/marketing/||' | sort -u > "$REFS"

DELETED=0
while IFS= read -r -d '' f; do
  rel="${f#./}"
  if ! grep -qxF "$rel" "$REFS"; then
    echo "DELETE $rel"
    rm -f "$f"
    DELETED=$((DELETED+1))
  fi
done < <(find . -type f \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' -o -name '*.avif' -o -name '*.png' \) -print0)

rm -f "$REFS"
echo "Deleted $DELETED unreferenced files."
