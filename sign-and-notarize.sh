#!/bin/bash
# Wired Server — Developer ID re-signing and notarization prep
set -e

SRC="/Users/maertin/Desktop/Wired Server 2026-03-29 19-00-56/Wired Server 29.03.26, 18.56.xcarchive/Products/Applications/Wired Server.app"
EXPORT="$HOME/Desktop/WiredServerExport"
APP="$EXPORT/Wired Server.app"
CERT="Developer ID Application: Joerg Maertin (VGB467J8DZ)"
ENT="/Users/maertin/Documents/WiredServer/Wired Server/Wired Server.entitlements"
HELPER_ENT="/Users/maertin/Documents/WiredServer/Wired Server Helper/Wired Server Helper.entitlements"
ZIP="$EXPORT/WiredServer.zip"

echo "=== 1. Copy app from archive ==="
rm -rf "$EXPORT"
mkdir -p "$EXPORT"
cp -a "$SRC" "$APP"

echo "=== 2. Sign wired binary (flat Mach-O, not a bundle) ==="
codesign --force --sign "$CERT" --options runtime \
    "$APP/Contents/Resources/Wired/wired"

echo "=== 3. Sign frameworks inside Wired Server Helper ==="
codesign --force --sign "$CERT" --options runtime \
    "$APP/Contents/Resources/Wired Server Helper.app/Contents/Frameworks/WiredAppKit.framework"
codesign --force --sign "$CERT" --options runtime \
    "$APP/Contents/Resources/Wired Server Helper.app/Contents/Frameworks/WiredFoundation.framework"

echo "=== 4. Sign Wired Server Helper ==="
codesign --force --sign "$CERT" --options runtime \
    --entitlements "$HELPER_ENT" \
    "$APP/Contents/Resources/Wired Server Helper.app"

echo "=== 5. Sign Sparkle's nested Autoupdate.app ==="
codesign --force --sign "$CERT" --options runtime \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/A/Resources/Autoupdate.app"

echo "=== 6. Sign main app frameworks ==="
codesign --force --sign "$CERT" --options runtime \
    "$APP/Contents/Frameworks/WiredAppKit.framework"
codesign --force --sign "$CERT" --options runtime \
    "$APP/Contents/Frameworks/WiredFoundation.framework"
codesign --force --sign "$CERT" --options runtime \
    "$APP/Contents/Frameworks/Sparkle.framework"

echo "=== 7. Sign main app ==="
codesign --force --sign "$CERT" --options runtime \
    --entitlements "$ENT" \
    "$APP"

echo "=== 8. Verify ==="
codesign --verify --deep --strict "$APP" && echo "Signature OK"

echo ""
echo "=== 9. Create zip for notarization ==="
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Zip created: $ZIP"

echo ""
echo "=== Done — ready for notarization ==="
echo ""
echo "Run this command (replace EMAIL and APPPASSWORD):"
echo ""
echo "  xcrun notarytool submit \"$ZIP\" \\"
echo "    --apple-id EMAIL \\"
echo "    --password APPPASSWORD \\"
echo "    --team-id VGB467J8DZ \\"
echo "    --wait"
echo ""
echo "After notarization succeeds:"
echo "  xcrun stapler staple \"$APP\""
