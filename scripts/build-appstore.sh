#!/bin/bash
# Builds the sandboxed, universal Mac App Store edition.
#
#   ./scripts/build-appstore.sh --local   ad-hoc signed, to try the sandboxed app on this Mac
#   ./scripts/build-appstore.sh           distribution-signed app and installer package for upload
#
# The upload build needs, from a paid Apple Developer Program membership:
#   - an "Apple Distribution" certificate and a "Mac Installer Distribution" certificate
#     in the keychain (found automatically; override with APP_IDENTITY / INSTALLER_IDENTITY)
#   - PROFILE=path/to/the Mac App Store provisioning profile for BUNDLE_ID
# Optional: BUNDLE_ID, VERSION, BUILD.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=WindowGrids
BUNDLE_ID="${BUNDLE_ID:-io.github.r2rka1.WindowGrids}"
APP="build/appstore/$NAME.app"
PB=/usr/libexec/PlistBuddy

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$NAME"

rm -rf build/appstore
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
PLIST="$APP/Contents/Info.plist"
cp Resources/Info.plist "$PLIST"

$PB -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
[[ -n "${VERSION:-}" ]] && $PB -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
[[ -n "${BUILD:-}" ]] && $PB -c "Set :CFBundleVersion $BUILD" "$PLIST"
# Keys Xcode normally adds; App Store validation looks for them.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
SDK_BUILD="$(xcrun --sdk macosx --show-sdk-build-version)"
XCODE="$(xcodebuild -version | awk '/^Xcode/ {split($2, v, "."); printf "%d%d%d", v[1], v[2], v[3]}')"
XCODE_BUILD="$(xcodebuild -version | awk '/^Build version/ {print $3}')"
$PB -c "Add :CFBundleSupportedPlatforms array" -c "Add :CFBundleSupportedPlatforms:0 string MacOSX" \
    -c "Add :CFBundleInfoDictionaryVersion string 6.0" \
    -c "Add :CFBundleDevelopmentRegion string en" \
    -c "Add :BuildMachineOSBuild string $(sw_vers -buildVersion)" \
    -c "Add :DTCompiler string com.apple.compilers.llvm.clang.1_0" \
    -c "Add :DTPlatformName string macosx" -c "Add :DTPlatformVersion string $SDK_VERSION" \
    -c "Add :DTPlatformBuild string $SDK_BUILD" \
    -c "Add :DTSDKName string macosx$SDK_VERSION" -c "Add :DTSDKBuild string $SDK_BUILD" \
    -c "Add :DTXcode string $XCODE" -c "Add :DTXcodeBuild string $XCODE_BUILD" "$PLIST"

ENT=build/appstore/entitlements.plist
cp Resources/AppStore.entitlements "$ENT"

if [[ "${1:-}" == "--local" ]]; then
    codesign --force --sign - --entitlements "$ENT" "$APP"
    echo "built $APP (sandboxed, ad-hoc signed; not for upload)"
    exit 0
fi

identity() { security find-identity -v 2>/dev/null | awk -F'"' -v re="$1" '$2 ~ re {print $2; exit}'; }
APP_IDENTITY="${APP_IDENTITY:-$(identity '^(Apple Distribution|3rd Party Mac Developer Application)')}"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-$(identity '^(Mac Installer Distribution|3rd Party Mac Developer Installer)')}"
if [[ -z "$APP_IDENTITY" || -z "$INSTALLER_IDENTITY" ]]; then
    echo "error: no distribution certificates in the keychain. See appstore/README.md." >&2
    exit 1
fi
if [[ -z "${PROFILE:-}" || ! -f "$PROFILE" ]]; then
    echo "error: set PROFILE to the Mac App Store provisioning profile. See appstore/README.md." >&2
    exit 1
fi
TEAM_ID="$(sed -E 's/.*\(([A-Z0-9]+)\)$/\1/' <<<"$APP_IDENTITY")"

cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
$PB -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" \
    -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ENT"
codesign --force --options runtime --timestamp --sign "$APP_IDENTITY" --entitlements "$ENT" "$APP"
codesign --verify --strict --verbose=2 "$APP"

PKG="build/appstore/$NAME.pkg"
productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
echo "built $PKG"
echo "Upload it with the Transporter app, or:"
echo "  xcrun altool --upload-package $PKG --type macos --apple-id <app id> \\"
echo "      --bundle-id $BUNDLE_ID --bundle-version <build> --bundle-short-version-string <version> \\"
echo "      --apiKey <key id> --apiIssuer <issuer id>"
