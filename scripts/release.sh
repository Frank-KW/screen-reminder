#!/usr/bin/env bash
# Build, sign, notarize and zip Screen Reminder for other Macs.
#
#   scripts/release.sh 1.0.0             real release (needs Developer ID + notary profile)
#   scripts/release.sh 1.0.0 --dry-run   same build, ad-hoc signed, no Apple upload
#
# Env:
#   NOTARY_PROFILE  keychain profile made with `xcrun notarytool store-credentials`
#                   (default: screen-reminder-notary)
#   BUILD_NUMBER    CFBundleVersion (default: 1)
set -euo pipefail

VERSION="${1:-}"
MODE="${2:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: scripts/release.sh <version like 1.0.0> [--dry-run]" >&2
  exit 2
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-screen-reminder-notary}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
DERIVED="$OUT/DerivedData"
APP_NAME="Screen Reminder"
ZIP="$OUT/Screen-Reminder-$VERSION.zip"

if [[ "$MODE" == "--dry-run" ]]; then
  SIGN_ARGS=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
  echo "Dry run: ad-hoc signing, no notarization."
else
  IDENTITY_LINE="$(security find-identity -v -p codesigning | grep '"Developer ID Application' | head -1 || true)"
  if [[ -z "$IDENTITY_LINE" ]]; then
    echo "No 'Developer ID Application' certificate in your keychain. See README, 'Releasing'." >&2
    exit 1
  fi
  IDENTITY_HASH="$(awk '{print $2}' <<<"$IDENTITY_LINE")"
  TEAM_ID="$(sed -E 's/.*\(([A-Z0-9]{10})\)".*/\1/' <<<"$IDENTITY_LINE")"
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Notary profile '$NOTARY_PROFILE' not found. See README, 'Releasing'." >&2
    exit 1
  fi
  SIGN_ARGS=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$IDENTITY_HASH" "DEVELOPMENT_TEAM=$TEAM_ID" "OTHER_CODE_SIGN_FLAGS=--timestamp")
fi

rm -rf "$OUT"
mkdir -p "$OUT"

xcodebuild \
  -project "$ROOT/ReminderApp.xcodeproj" \
  -scheme ReminderApp \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  "${SIGN_ARGS[@]}" \
  ENABLE_HARDENED_RUNTIME=YES \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" \
  clean build | grep -E "error:|warning: |BUILD" || true

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "Build failed: $APP not found." >&2; exit 1; }

codesign --verify --deep --strict --verbose=2 "$APP"

if [[ "$MODE" != "--dry-run" ]]; then
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
  rm -f "$ZIP"
fi

ditto -c -k --keepParent "$APP" "$ZIP"
echo
echo "Ready: $ZIP"
shasum -a 256 "$ZIP"
