#!/bin/bash
# refresh-sideload.sh
# Rebuilds HouseholdApp and reinstalls it on all paired iPhones.
# Run manually or via launchd weekly to keep the 7-day sideload certificate fresh.
#
# Prerequisites:
#   - Wireless pairing enabled in Xcode for each device
#     (Window → Devices and Simulators → check "Connect via Network")
#   - Phones on the same WiFi as this Mac when the script runs

set -e

PROJECT_DIR="/Users/jordanadamich/Coding/HouseholdApp"
SCHEME="HouseholdApp"
DERIVED_DATA_APP="$HOME/Library/Developer/Xcode/DerivedData/HouseholdApp-btmbjbnnmvrsgodipeaswnzziody/Build/Products/Debug-iphoneos/HouseholdApp.app"

# ── Device UDIDs ──────────────────────────────────────────────────────────────
JORDAN_IPHONE="00008101-000838881AE1001E"
# WIFE_IPHONE=""   # Add after wireless-pairing her phone in Xcode

DEVICES=("$JORDAN_IPHONE")
# Uncomment once wife's phone is paired:
# DEVICES=("$JORDAN_IPHONE" "$WIFE_IPHONE")

echo "▶ Building HouseholdApp for device..."
xcodebuild \
  -project "$PROJECT_DIR/HouseholdApp.xcodeproj" \
  -scheme "$SCHEME" \
  -destination "id=$JORDAN_IPHONE" \
  -configuration Debug \
  build 2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)|Compiling|Linking"

echo "▶ Installing on devices..."
for UDID in "${DEVICES[@]}"; do
  echo "  → $UDID"
  xcrun devicectl device install app \
    --device "$UDID" \
    --bundle-path "$DERIVED_DATA_APP"
done

echo "✅ HouseholdApp refreshed on all devices!"
