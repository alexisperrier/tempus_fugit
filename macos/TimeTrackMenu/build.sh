#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="TimeTrackMenu"
BUNDLE_ID="${BUNDLE_ID:-com.alexis.timetrack.menu}"
REPO_PATH="$(cd ../.. && pwd)"
APP="${APP_NAME}.app"
CONTENTS="${APP}/Contents"
# A stable signing identity keeps Accessibility / Automation permissions across
# rebuilds. Create it once (see README.md); otherwise we fall back to ad-hoc.
SIGN_IDENTITY="${SIGN_IDENTITY:-TimeTrack Dev}"

echo "==> Compiling ${APP_NAME}"
mkdir -p build
swiftc -O -parse-as-library \
    -framework SwiftUI \
    -framework AppKit \
    -framework Combine \
    -framework ApplicationServices \
    -o "build/${APP_NAME}" \
    src/*.swift

echo "==> Assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"
cp "build/${APP_NAME}" "${CONTENTS}/MacOS/${APP_NAME}"

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>     <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleShortVersionString</key> <string>0.1</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>15.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>LSUIElement</key>             <true/>
    <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>
    <key>TimeTrackRepoPath</key>       <string>${REPO_PATH}</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>TimeTrack reads the active tab URL from your browser to track time per website.</string>
</dict>
</plist>
PLIST

if security find-identity -p codesigning 2>/dev/null | grep -q "\"${SIGN_IDENTITY}\""; then
    echo "==> Signing with '${SIGN_IDENTITY}'"
    codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP}"
else
    echo "==> '${SIGN_IDENTITY}' not found: ad-hoc signing (permissions must be re-granted after each rebuild)"
    codesign --force --deep --sign - "${APP}"
fi
codesign --verify --verbose "${APP}"

echo "==> Done: $(pwd)/${APP}"
