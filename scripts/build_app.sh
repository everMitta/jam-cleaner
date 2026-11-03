#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/JAM Cleaner.app"
LEGACY_APP_BUNDLE="${BUILD_DIR}/MacSweep.app"
CHANNEL="${CHANNEL:-${BUILD_MODE:-direct}}"           # "direct" (Developer ID / local) or "appstore" (Mac App Store Sandbox)
SIGNING_IDENTITY="${SIGNING_IDENTITY:-${SIGN_IDENTITY:--}}"
BUILD_UNIVERSAL="${BUILD_UNIVERSAL:-0}"

cd "${PROJECT_DIR}"
mkdir -p "${BUILD_DIR}"

if [[ "${BUILD_UNIVERSAL}" == "1" ]]; then
    echo "🔨 Building JAM Cleaner Universal Binary (arm64 + x86_64 Release)..."
    swift build -c release --arch arm64 --arch x86_64
    BIN_PATH="${PROJECT_DIR}/.build/apple/Products/Release/MacSweep"
else
    echo "🔨 Building JAM Cleaner (Release)..."
    swift build -c release
    BIN_PATH="$(swift build -c release --show-bin-path)/MacSweep"
fi

rm -rf "${APP_BUNDLE}" "${LEGACY_APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Create localization folders so macOS and App Store Connect detect English, Spanish, and French support
for lang in en es fr; do
    mkdir -p "${APP_BUNDLE}/Contents/Resources/${lang}.lproj"
done

cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/MacSweep"
chmod +x "${APP_BUNDLE}/Contents/MacOS/MacSweep"

# Bundle Apple Required Reason API Privacy Manifest (Mandatory for App Store Connect)
cp "${PROJECT_DIR}/Config/PrivacyInfo.xcprivacy" "${APP_BUNDLE}/Contents/Resources/PrivacyInfo.xcprivacy"

# Generate multi-resolution Retina AppIcon.icns (regenerated if missing or if generator script is newer)
CACHED_ICNS="${BUILD_DIR}/AppIcon.icns"
if [[ ! -f "${CACHED_ICNS}" || "${PROJECT_DIR}/scripts/generate_app_icon.swift" -nt "${CACHED_ICNS}" ]]; then
    echo "🎨 Generating multi-resolution Retina AppIcon.icns for JAM Cleaner..."
    ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"
    rm -rf "${ICONSET_DIR}"
    swift "${PROJECT_DIR}/scripts/generate_app_icon.swift" "${ICONSET_DIR}"
    iconutil -c icns "${ICONSET_DIR}" -o "${CACHED_ICNS}"
    rm -rf "${ICONSET_DIR}"
fi
cp "${CACHED_ICNS}" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

cat > "${APP_BUNDLE}/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>es</string>
        <string>fr</string>
    </array>
    <key>CFBundleDisplayName</key>
    <string>JAM Cleaner</string>
    <key>CFBundleExecutable</key>
    <string>MacSweep</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.innoteclabs.jamcleaner</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>JAM Cleaner</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Innotec Labs &amp; JAM Cleaner Contributors. Released under the MIT License.</string>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
    <key>NSAppleEventsUsageDescription</key>
    <string>JAM Cleaner uses Apple Events to gracefully close open applications before cleaning their active cache files when requested by the user.</string>
    <key>NSSystemAdministrationUsageDescription</key>
    <string>JAM Cleaner inspects and cleans regenerable system and application caches to reclaim disk space.</string>
</dict>
</plist>
EOF

if [[ "${CHANNEL}" == "appstore" ]]; then
    ENTITLEMENTS_PATH="${PROJECT_DIR}/Config/MacSweep.AppStore.entitlements"
else
    ENTITLEMENTS_PATH="${PROJECT_DIR}/Config/MacSweep.Direct.entitlements"
fi

echo "🔐 Signing ${APP_BUNDLE} (Channel: ${CHANNEL}, Identity: ${SIGNING_IDENTITY})..."
codesign --force --options runtime --entitlements "${ENTITLEMENTS_PATH}" --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
cp -R "${APP_BUNDLE}" "${LEGACY_APP_BUNDLE}"
echo "✅ Packaged ${APP_BUNDLE}"
