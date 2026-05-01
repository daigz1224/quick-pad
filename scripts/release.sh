#!/usr/bin/env bash
# Build and package QuickPad as an ad-hoc-signed Universal .zip ready
# for casual distribution (no Apple Developer Program required).
#
# Usage:
#   scripts/release.sh                # full pipeline: test → build → zip
#   scripts/release.sh --skip-tests   # bypass the test suite
#   scripts/release.sh --help

set -euo pipefail

show_help() {
    cat <<'HELP'
release.sh — build + package QuickPad for ad-hoc distribution.

Steps:
  1. xcodegen generate           (refresh Xcode project from project.yml)
  2. xcodebuild test             (skip with --skip-tests)
  3. xcodebuild Release          (Universal: arm64 + x86_64)
  4. Verify Universal + signed
  5. ditto into dist/QuickPad-<version>.zip

Recipient instructions (zip is ad-hoc signed, not notarized):
  - Drag QuickPad.app to /Applications.
  - First launch hits Gatekeeper. Right-click → Open in Finder, or:
      xattr -cr /Applications/QuickPad.app
HELP
}

# Resolve repo root from this script's location so the script works
# regardless of CWD when invoked.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Args
SKIP_TESTS=0
for arg in "$@"; do
    case "$arg" in
        --skip-tests) SKIP_TESTS=1 ;;
        -h|--help)    show_help; exit 0 ;;
        *) echo "unknown arg: $arg (try --help)"; exit 64 ;;
    esac
done

# Preconditions
[[ -f project.yml ]] || { echo "error: project.yml not found at $REPO_ROOT"; exit 1; }
command -v xcodegen   >/dev/null || { echo "error: xcodegen missing — brew install xcodegen"; exit 1; }
command -v xcodebuild >/dev/null || { echo "error: xcodebuild missing — install Xcode"; exit 1; }

# Cleanup
echo "==> Cleaning previous artifacts"
rm -rf build dist
mkdir -p build dist

# Generate
echo "==> Generating Xcode project (xcodegen)"
xcodegen generate >/dev/null

# Test (capture output; only show on failure to keep the log scannable)
if [[ $SKIP_TESTS -eq 0 ]]; then
    echo "==> Running test suite"
    if ! xcodebuild -project QuickPad.xcodeproj -scheme QuickPad \
          -configuration Debug \
          -derivedDataPath build/test \
          -destination 'platform=macOS' \
          test > build/test.log 2>&1; then
        echo "  ✗ Tests failed. Last 30 lines:"
        tail -30 build/test.log
        exit 1
    fi
    PASS_LINE=$(grep -E "Executed [0-9]+ tests" build/test.log | tail -1)
    echo "  ✓ ${PASS_LINE:-tests passed}"
fi

# Build (Release auto-selects ONLY_ACTIVE_ARCH=NO → Universal)
echo "==> Release build (Universal: arm64 + x86_64)"
if ! xcodebuild -project QuickPad.xcodeproj -scheme QuickPad \
      -configuration Release \
      -derivedDataPath build \
      clean build > build/release.log 2>&1; then
    echo "  ✗ Build failed. Last 30 lines:"
    tail -30 build/release.log
    exit 1
fi

APP="$REPO_ROOT/build/Build/Products/Release/QuickPad.app"
[[ -d "$APP" ]] || { echo "  ✗ build succeeded but $APP is missing"; exit 1; }

# Verify
echo "==> Verifying"
if file "$APP/Contents/MacOS/QuickPad" | grep -q "universal"; then
    echo "  ✓ Universal binary"
else
    # Universal isn't strictly required but is the expected default;
    # fail loudly so a misconfigured Release build doesn't ship arm-only.
    echo "  ✗ NOT a universal binary"
    file "$APP/Contents/MacOS/QuickPad"
    exit 1
fi

if codesign --verify --strict "$APP" 2>/dev/null; then
    SIG_KIND=$(codesign -dvv "$APP" 2>&1 | awk -F= '/Signature=/ {print $2}')
    echo "  ✓ Code signature valid (${SIG_KIND:-unknown})"
else
    echo "  ✗ codesign --verify failed"; exit 1
fi

VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
ZIP="$REPO_ROOT/dist/QuickPad-$VERSION.zip"

# Package — ditto preserves Mach-O signatures and macOS metadata; plain
# zip(1) would strip extended attributes and break the ad-hoc signature.
echo "==> Packaging $(basename "$ZIP")"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

APP_SIZE=$(du -sh "$APP" | cut -f1)
ZIP_SIZE=$(du -sh "$ZIP" | cut -f1)

echo
echo "═══════════════════════════════════════════════════════════"
echo "  QuickPad $VERSION ready for distribution"
echo "═══════════════════════════════════════════════════════════"
echo "  zip:  $ZIP"
echo "  size: $ZIP_SIZE (uncompressed app: $APP_SIZE)"
echo
echo "  Tell recipients:"
echo "    1. Unzip, drag QuickPad.app to /Applications."
echo "    2. First launch: right-click → Open in Finder, or:"
echo "         xattr -cr /Applications/QuickPad.app"
