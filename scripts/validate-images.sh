#!/usr/bin/env bash
# HandzJ Digital Receipts — Quick Image Validation (bash)
# Exit code 0 = pass, 1 = fail
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKETING="$ROOT/public/assets/marketing"
PUBLIC="$ROOT/public"
STRICT=0
[[ "${1:-}" == "--strict" ]] && STRICT=1

ERRORS=0
WARNINGS=0

red()  { printf "\033[31m%s\033[0m\n" "$*"; }
yel()  { printf "\033[33m%s\033[0m\n" "$*"; }
grn()  { printf "\033[32m%s\033[0m\n" "$*"; }

echo "HandzJ Image Validation (bash)"
echo "=============================="
echo "Marketing: $MARKETING"
echo

if [[ ! -d "$MARKETING" ]]; then
  red "ERROR: marketing directory missing"
  exit 2
fi

# 1. HTML references
echo "→ Checking HTML references..."
TMPREFS=$(mktemp)
grep -ohE '/assets/marketing/[a-zA-Z0-9._-]+\.(jpg|jpeg|webp|avif|png)' "$PUBLIC"/*.html 2>/dev/null \
  | sed 's|.*/||' | sort -u > "$TMPREFS" || true

while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  path="$MARKETING/$ref"
  if [[ ! -f "$path" ]]; then
    red "  MISSING: $ref (referenced in HTML)"
    ERRORS=$((ERRORS + 1))
  elif [[ ! -s "$path" ]]; then
    red "  EMPTY:   $ref (0 bytes)"
    ERRORS=$((ERRORS + 1))
  fi
done < "$TMPREFS"
rm -f "$TMPREFS"

# 2. Complete size sets
KNOWN_SETS=(
  hands-verify-valid
  receipt-phone-and-print
  desk-owner-and-verify
  hero-verify-phone
  market-vendor-valid
  hardware-phone-print
  beauty-lounge-valid
  phone-repair-valid
)
ORIGINAL_SETS="hands-verify-valid|receipt-phone-and-print|desk-owner-and-verify|hero-verify-phone"

echo "→ Checking complete size sets..."
for base in "${KNOWN_SETS[@]}"; do
  for size in 640 960 1168; do
    for fmt in jpg webp avif; do
      f="$MARKETING/${base}-${size}.${fmt}"
      if [[ ! -f "$f" ]]; then
        if [[ "$fmt" == "avif" ]] && [[ "$base" =~ ^($ORIGINAL_SETS)$ ]]; then
          yel "  WARN: optional AVIF missing — ${base}-${size}.avif"
          WARNINGS=$((WARNINGS + 1))
        else
          red "  MISSING: ${base}-${size}.${fmt}"
          ERRORS=$((ERRORS + 1))
        fi
      elif [[ ! -s "$f" ]]; then
        red "  EMPTY:   ${base}-${size}.${fmt}"
        ERRORS=$((ERRORS + 1))
      fi
    done
  done
done

# 3. Dimensions
if command -v identify >/dev/null 2>&1; then
  echo "→ Checking dimensions..."
  for base in market-vendor-valid hardware-phone-print hands-verify-valid receipt-phone-and-print desk-owner-and-verify hero-verify-phone; do
    f="$MARKETING/${base}-1168.jpg"
    [[ -f "$f" ]] || continue
    wh=$(identify -format "%w %h" "$f")
    w=${wh%% *}; h=${wh##* }
    if (( w < h )); then
      red "  ORIENTATION: $f is portrait (${w}x${h}) but expected landscape"
      ERRORS=$((ERRORS + 1))
    fi
  done
  for base in beauty-lounge-valid phone-repair-valid; do
    f="$MARKETING/${base}-1168.jpg"
    [[ -f "$f" ]] || continue
    wh=$(identify -format "%w %h" "$f")
    w=${wh%% *}; h=${wh##* }
    if (( h < w )); then
      red "  ORIENTATION: $f is landscape (${w}x${h}) but expected portrait"
      ERRORS=$((ERRORS + 1))
    fi
  done
else
  yel "  (identify not found – skipping dimension checks)"
fi

echo
echo "------------------------------"
echo "Errors   : $ERRORS"
echo "Warnings : $WARNINGS"

if (( ERRORS > 0 )) || { (( STRICT )) && (( WARNINGS > 0 )); }; then
  red "RESULT: FAIL"
  exit 1
else
  grn "RESULT: PASS"
  exit 0
fi
