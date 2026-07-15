#!/usr/bin/env bash
# Horizon — local TestFlight upload (Mac Catalyst).
#
# Mac counterpart to upload-testflight.sh. Archives the SAME Horizon scheme for
# the Mac Catalyst variant (same bundle id — Universal Purchase), exports a
# signed .pkg, and uploads it to App Store Connect for Mac TestFlight.
#
# Usage:
#   ./scripts/upload-testflight-mac.sh   (or: make ship-mac)
#
# Prerequisites (one-time, on Apple's side):
#   1. App ID com.stephanieraymos.horizon registered (Mac Catalyst inherits it).
#   2. The iOS app record already exists; the Mac build attaches to it.
#   3. "Apple Distribution" + "3rd Party Mac Developer Installer" (a.k.a.
#      "Apple Distribution"/"Mac Installer Distribution") certs in your Keychain
#      — these already exist from shipping your other Mac apps.

set -euo pipefail

cd "$(dirname "$0")/.."

# --- Config ---
SCHEME="Horizon"
PROJECT="Horizon.xcodeproj"
TEAM="FZ5HL2XU6U"
ARCHIVE_PATH="build/Horizon-mac.xcarchive"
EXPORT_PATH="build/export-mac"
ASC_KEY_FILE="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Cowork OS/Projects/Spect - Health Tracker/Resources/AuthKey_RJ7CKLZFFX.p8"
ASC_KEY_ID="RJ7CKLZFFX"
ASC_ISSUER_ID="4e55d966-9145-4f15-bfc6-c698befe9a66"

# --- Sanity checks ---
[ -f "$ASC_KEY_FILE" ] || { echo "❌ Missing ASC API key at: $ASC_KEY_FILE"; exit 1; }
command -v xcodegen   >/dev/null || { echo "❌ xcodegen not found (brew install xcodegen)"; exit 1; }
command -v xcodebuild >/dev/null || { echo "❌ xcodebuild not found (install Xcode)"; exit 1; }

echo "▶  Regenerating Xcode project..."
xcodegen generate >/dev/null

mkdir -p "$HOME/.private_keys"
cp "$ASC_KEY_FILE" "$HOME/.private_keys/AuthKey_${ASC_KEY_ID}.p8"

echo "▶  Resolving Swift packages..."
xcodebuild -resolvePackageDependencies -scheme "$SCHEME" -project "$PROJECT" >/dev/null

BUILD_NUMBER=$(date +%s)
echo "▶  Archiving Mac Catalyst (build number $BUILD_NUMBER)..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

xcodebuild archive \
  -scheme "$SCHEME" \
  -project "$PROJECT" \
  -destination "generic/platform=macOS,variant=Mac Catalyst" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$HOME/.private_keys/AuthKey_${ASC_KEY_ID}.p8" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  DEVELOPMENT_TEAM="$TEAM" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -quiet

echo "▶  Exporting .pkg..."
# Manual signing: ExportOptions-mac.plist pins the "Horizon Mac App Store"
# provisioning profile + Apple Distribution cert, so the export signs entirely
# from the local keychain — no Xcode account or cloud-managed distribution
# signing (the shared ASC API key lacks the App Manager role for that). This
# mirrors how the other Mac apps (SpectMac, bread-mac, orbit-mac) ship.
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist ExportOptions-mac.plist \
  -quiet

PKG=$(find "$EXPORT_PATH" -name '*.pkg' | head -1)
[ -n "$PKG" ] || { echo "❌ No .pkg found in $EXPORT_PATH"; exit 1; }
echo "▶  Package ready: $PKG"

echo "▶  Uploading to TestFlight..."
set +e
xcrun altool --upload-app \
  --type macos \
  --file "$PKG" \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID" \
  --verbose 2>&1 | tee /tmp/horizon-altool-mac.log
UPLOAD_EXIT=$?
set -e

if grep -qE "UPLOAD FAILED|Validation failed|ERROR ITMS-" /tmp/horizon-altool-mac.log; then
  echo "❌ altool reported a validation/upload failure (see /tmp/horizon-altool-mac.log)"
  exit 1
fi
if [ $UPLOAD_EXIT -ne 0 ]; then
  echo "❌ altool exited $UPLOAD_EXIT"
  exit $UPLOAD_EXIT
fi

echo ""
echo "✅ Upload complete. Mac build $BUILD_NUMBER will appear in App Store Connect"
echo "   → TestFlight (macOS) after processing."
