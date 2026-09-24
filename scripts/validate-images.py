#!/usr/bin/env python3
"""
HandzJ Digital Receipts — Automated Image Validation Script
===========================================================
Validates marketing images for:
  1. Existence of every HTML-referenced file
  2. Complete size variants (640 / 960 / 1168) for known sets
  3. Correct formats (jpg, webp, avif)
  4. Non-zero file sizes
  5. Expected dimensions (landscape vs portrait)
  6. Naming consistency

Usage:
  python3 scripts/validate-images.py
  python3 scripts/validate-images.py --strict   # treat warnings as errors
  python3 scripts/validate-images.py --json     # machine-readable output
"""

from __future__ import annotations
import argparse
import json
import re
import sys
from pathlib import Path
from collections import defaultdict

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

ROOT = Path(__file__).resolve().parent.parent
PUBLIC = ROOT / "public"
MARKETING = PUBLIC / "assets" / "marketing"
HTML_GLOB = "*.html"

# Known responsive sets and their expected orientation
KNOWN_SETS = {
    # Existing original sets
    "hands-verify-valid": "landscape",
    "receipt-phone-and-print": "landscape",
    "desk-owner-and-verify": "landscape",
    "hero-verify-phone": "landscape",
    # New sets
    "market-vendor-valid": "landscape",
    "hardware-phone-print": "landscape",
    "beauty-lounge-valid": "portrait",
    "phone-repair-valid": "portrait",
}

SIZES = ["", "-640", "-960", "-1168"]  # "" = master
FORMATS = ["jpg", "webp", "avif"]

# Expected max dimensions (approximate)
LANDSCAPE_MAX = (1168, 784)
PORTRAIT_MAX = (784, 1168)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def get_dimensions(path: Path) -> tuple[int, int] | None:
    if not HAS_PIL:
        return None
    try:
        with Image.open(path) as im:
            return im.size
    except Exception:
        return None


def collect_html_references() -> dict[str, list[str]]:
    """Return {filename: [html_files_that_reference_it]}"""
    refs: dict[str, list[str]] = defaultdict(list)
    pattern = re.compile(r'/assets/marketing/([a-z0-9\-]+\.(?:jpg|webp|avif|png|svg))', re.I)

    for html in PUBLIC.glob(HTML_GLOB):
        content = html.read_text(encoding="utf-8", errors="ignore")
        for match in pattern.finditer(content):
            fname = match.group(1)
            refs[fname].append(html.name)
    return refs


def check_file_exists(path: Path) -> tuple[bool, str]:
    if not path.exists():
        return False, "MISSING"
    if path.stat().st_size == 0:
        return False, "EMPTY (0 bytes)"
    return True, "OK"


# ---------------------------------------------------------------------------
# Validation rules
# ---------------------------------------------------------------------------

def validate_html_references() -> list[dict]:
    issues = []
    refs = collect_html_references()
    for fname, pages in sorted(refs.items()):
        path = MARKETING / fname
        ok, status = check_file_exists(path)
        if not ok:
            issues.append({
                "level": "error",
                "rule": "html-reference",
                "file": fname,
                "message": f"Referenced in {', '.join(pages)} but file is {status}",
                "pages": pages,
            })
    return issues


def validate_complete_sets() -> list[dict]:
    issues = []
    for base, orientation in KNOWN_SETS.items():
        for size in SIZES:
            for fmt in FORMATS:
                # Masters may not have every format historically; only enforce sizes
                if size == "" and fmt in ("webp", "avif"):
                    # Optional for masters – warn only
                    path = MARKETING / f"{base}.{fmt}"
                    if not path.exists():
                        issues.append({
                            "level": "warning",
                            "rule": "master-format",
                            "file": f"{base}.{fmt}",
                            "message": f"Master {fmt} missing (optional)",
                        })
                    continue

                fname = f"{base}{size}.{fmt}"
                path = MARKETING / fname
                ok, status = check_file_exists(path)
                if not ok:
                    # Original sets never received AVIF – treat as warning only
                    is_original = base in {
                        "hands-verify-valid", "receipt-phone-and-print",
                        "desk-owner-and-verify", "hero-verify-phone"
                    }
                    level = "warning" if (fmt == "avif" and is_original) else "error"
                    issues.append({
                        "level": level,
                        "rule": "complete-set",
                        "file": fname,
                        "message": f"Required variant missing or {status}",
                    })
    return issues


def validate_dimensions() -> list[dict]:
    issues = []
    if not HAS_PIL:
        issues.append({
            "level": "warning",
            "rule": "dimensions",
            "file": "-",
            "message": "Pillow not installed – skipping dimension checks",
        })
        return issues

    for base, orientation in KNOWN_SETS.items():
        # Check the 1168 variant as the canonical size
        path = MARKETING / f"{base}-1168.jpg"
        if not path.exists():
            continue
        dims = get_dimensions(path)
        if not dims:
            issues.append({
                "level": "error",
                "rule": "dimensions",
                "file": path.name,
                "message": "Could not read image dimensions",
            })
            continue

        w, h = dims
        if orientation == "landscape":
            if w < h:
                issues.append({
                    "level": "error",
                    "rule": "dimensions",
                    "file": path.name,
                    "message": f"Expected landscape but got {w}x{h} (portrait)",
                })
            if abs(w - LANDSCAPE_MAX[0]) > 20 or abs(h - LANDSCAPE_MAX[1]) > 20:
                issues.append({
                    "level": "warning",
                    "rule": "dimensions",
                    "file": path.name,
                    "message": f"Unexpected size {w}x{h} (expected ~{LANDSCAPE_MAX[0]}x{LANDSCAPE_MAX[1]})",
                })
        else:  # portrait
            if h < w:
                issues.append({
                    "level": "error",
                    "rule": "dimensions",
                    "file": path.name,
                    "message": f"Expected portrait but got {w}x{h} (landscape)",
                })
            if abs(w - PORTRAIT_MAX[0]) > 20 or abs(h - PORTRAIT_MAX[1]) > 20:
                issues.append({
                    "level": "warning",
                    "rule": "dimensions",
                    "file": path.name,
                    "message": f"Unexpected size {w}x{h} (expected ~{PORTRAIT_MAX[0]}x{PORTRAIT_MAX[1]})",
                })
    return issues


def validate_orphan_files() -> list[dict]:
    """Warn about files in marketing/ that are never referenced (optional)."""
    issues = []
    refs = set(collect_html_references().keys())
    for path in MARKETING.iterdir():
        if not path.is_file():
            continue
        if path.suffix.lower() not in (".jpg", ".jpeg", ".webp", ".avif", ".png"):
            continue
        if path.name.startswith("README"):
            continue
        # Allow masters and sized variants even if only some sizes are referenced
        base = re.sub(r'-(640|960|1168)\.(jpg|webp|avif)$', '', path.name)
        base = re.sub(r'\.(jpg|webp|avif)$', '', base)
        # If the base is a known set, it's fine
        if any(base.startswith(k) or k.startswith(base) for k in KNOWN_SETS):
            continue
        if path.name not in refs:
            issues.append({
                "level": "info",
                "rule": "orphan",
                "file": path.name,
                "message": "File exists but is not referenced in any HTML",
            })
    return issues


def validate_naming_consistency() -> list[dict]:
    """Check that filenames follow the expected pattern."""
    issues = []
    pattern = re.compile(r'^[a-z0-9]+(-[a-z0-9]+)*(-(640|960|1168))?\.(jpg|webp|avif)$')
    for path in MARKETING.iterdir():
        if not path.is_file():
            continue
        if path.suffix.lower() not in (".jpg", ".webp", ".avif"):
            continue
        if path.name.startswith("README"):
            continue
        if not pattern.match(path.name):
            issues.append({
                "level": "warning",
                "rule": "naming",
                "file": path.name,
                "message": "Filename does not match expected kebab-case + optional size pattern",
            })
    return issues


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Validate HandzJ marketing images")
    parser.add_argument("--strict", action="store_true", help="Treat warnings as errors")
    parser.add_argument("--json", action="store_true", help="Output JSON")
    parser.add_argument("--quiet", action="store_true", help="Only print summary / errors")
    args = parser.parse_args()

    if not MARKETING.exists():
        print(f"ERROR: Marketing directory not found: {MARKETING}", file=sys.stderr)
        sys.exit(2)

    all_issues = []
    all_issues.extend(validate_html_references())
    all_issues.extend(validate_complete_sets())
    all_issues.extend(validate_dimensions())
    all_issues.extend(validate_naming_consistency())
    all_issues.extend(validate_orphan_files())

    errors = [i for i in all_issues if i["level"] == "error"]
    warnings = [i for i in all_issues if i["level"] == "warning"]
    infos = [i for i in all_issues if i["level"] == "info"]

    if args.json:
        print(json.dumps({
            "errors": errors,
            "warnings": warnings,
            "infos": infos,
            "summary": {
                "error_count": len(errors),
                "warning_count": len(warnings),
                "info_count": len(infos),
                "pass": len(errors) == 0 and (not args.strict or len(warnings) == 0),
            }
        }, indent=2))
    else:
        if not args.quiet:
            print("HandzJ Image Validation Report")
            print("=" * 40)
            print(f"Marketing dir : {MARKETING}")
            print(f"Known sets    : {len(KNOWN_SETS)}")
            print()

        def print_group(title, items, symbol):
            if not items:
                return
            print(f"\n{symbol} {title} ({len(items)})")
            for i in items:
                print(f"  [{i['rule']}] {i['file']}")
                print(f"       {i['message']}")

        print_group("ERRORS", errors, "✗")
        print_group("WARNINGS", warnings, "⚠")
        if not args.quiet:
            print_group("INFO", infos, "ℹ")

        print()
        print("-" * 40)
        print(f"Errors   : {len(errors)}")
        print(f"Warnings : {len(warnings)}")
        print(f"Info     : {len(infos)}")

        if errors or (args.strict and warnings):
            print("\nRESULT: FAIL")
            sys.exit(1)
        else:
            print("\nRESULT: PASS")
            sys.exit(0)


if __name__ == "__main__":
    main()
