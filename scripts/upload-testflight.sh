#!/usr/bin/env bash
# Horizon — local TestFlight upload (iOS).
#
# Archives the Horizon scheme, exports a signed IPA, and uploads it to App Store
# Connect for iOS TestFlight. Uses the account-wide App Store Connect API key
# (shared with Orbit / Glade / Spect) plus automatic signing, so there are no
# per-app provisioning profiles to download — Xcode creates the distribution
# profile on the fly via -allowProvisioningUpdates.
#
# Usage:
#   ./scripts/upload-testflight.sh   (or: make ship)
#
# Prerequisites (one-time, on Apple's side):
#   1. App ID com.stephanieraymos.horizon registered in the Developer portal.
#   2. An app record for that bundle ID created in App Store Connect.
#   3. An "Apple Distribution: Stephanie Raymos" cert in your local Keychain.
#
# Build number: CFBundleVersion is set to $(date +%s) so every run gets a
# unique, monotonically increasing build number.

set -euo pipefail

cd "$(dirname "$0")/.."

# --- Config ---
SCHEME="Horizon"
PROJECT="Horizon.xcodeproj"
TEAM="FZ5HL2XU6U"
ARCHIVE_PATH="build/Horizon.xcarchive"
EXPORT_PATH="build/export"
# Account-wide ASC API key, shared across all of Stephanie's apps.
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
echo "▶  Archiving iOS (build number $BUILD_NUMBER)..."
rm -rf build

# Archive with retry — Apple's signing service intermittently returns 401 /
# "Communication with Apple failed" / timeouts.
ARCHIVE_LOG=/tmp/horizon-archive.log
attempt=1
max_attempts=3
while true; do
  set +e
  xcodebuild archive \
    -scheme "$SCHEME" \
    -project "$PROJECT" \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$HOME/.private_keys/AuthKey_${ASC_KEY_ID}.p8" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    DEVELOPMENT_TEAM="$TEAM" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    -quiet 2>&1 | tee "$ARCHIVE_LOG"
  ARCHIVE_EXIT=${PIPESTATUS[0]}
  set -e

  if [ "$ARCHIVE_EXIT" -eq 0 ]; then break; fi

  if grep -qE "Communication with Apple failed|request timed out|A non-HTTP 200 response was received \(401\)|DVTPortalResponseError" "$ARCHIVE_LOG" \
     && [ "$attempt" -lt "$max_attempts" ]; then
    echo "⚠️  Transient Apple signing failure (attempt $attempt/$max_attempts). Retrying in 15s..."
    sleep 15
    attempt=$((attempt + 1))
    rm -rf "$ARCHIVE_PATH"
    continue
  fi

  echo "❌ Archive failed (exit $ARCHIVE_EXIT). See $ARCHIVE_LOG"
  exit "$ARCHIVE_EXIT"
done

echo "▶  Exporting IPA..."
# NOTE: export intentionally does NOT pass the ASC API key. Cloud-managed
# *distribution* signing isn't permitted for this key ("Cloud signing permission
# error"), but Xcode's logged-in account can create the App Store profile. So
# export relies on the local account + Apple Distribution cert in the Keychain.
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates \
  -quiet

IPA=$(find "$EXPORT_PATH" -name '*.ipa' | head -1)
[ -n "$IPA" ] || { echo "❌ No IPA found in $EXPORT_PATH"; exit 1; }
echo "▶  IPA ready: $IPA"

echo "▶  Uploading to TestFlight..."
set +e
xcrun altool --upload-app \
  --type ios \
  --file "$IPA" \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID" \
  --verbose 2>&1 | tee /tmp/horizon-altool.log
UPLOAD_EXIT=$?
set -e

if grep -qE "UPLOAD FAILED|Validation failed|ERROR ITMS-" /tmp/horizon-altool.log; then
  echo "❌ altool reported a validation/upload failure (see /tmp/horizon-altool.log)"
  exit 1
fi
if [ $UPLOAD_EXIT -ne 0 ]; then
  echo "❌ altool exited $UPLOAD_EXIT"
  exit $UPLOAD_EXIT
fi

echo ""
echo "✅ Upload complete. Build $BUILD_NUMBER will appear in App Store Connect"
echo "   → TestFlight in 5–10 minutes after processing."
