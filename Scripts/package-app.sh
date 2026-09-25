#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-debug}"

# Keep development and release TCC identities separate. The release Bundle ID
# must remain stable so macOS preserves user permissions across updates.
if [[ -n "${SAYKUKU_BUNDLE_IDENTIFIER:-}" ]]; then
    BUNDLE_IDENTIFIER="$SAYKUKU_BUNDLE_IDENTIFIER"
elif [[ "$CONFIGURATION" == "release" ]]; then
    BUNDLE_IDENTIFIER="com.saykuku.app"
else
    BUNDLE_IDENTIFIER="com.saykuku.dev"
fi

if [[ "$CONFIGURATION" == "release" && "$BUNDLE_IDENTIFIER" != "com.saykuku.app" ]]; then
    print -u2 "Release builds must use Bundle ID com.saykuku.app"
    exit 1
fi
if [[ "$CONFIGURATION" != "release" && "$BUNDLE_IDENTIFIER" == "com.saykuku.app" ]]; then
    print -u2 "Development builds must not use the release Bundle ID com.saykuku.app"
    exit 1
fi

# macOS 15 still runs on Intel, so release builds ship a universal binary.
BUILD_ARGS=(-c "$CONFIGURATION")
if [[ "$CONFIGURATION" == "release" ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

cd "$ROOT_DIR"
swift build "${BUILD_ARGS[@]}"

PRODUCT_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP_DIR="$ROOT_DIR/Build/SayKuku.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$PRODUCT_DIR/SayKuku" "$APP_DIR/Contents/MacOS/SayKuku"
if [[ "$CONFIGURATION" == "release" ]]; then
    ARCHS=" $(lipo -archs "$APP_DIR/Contents/MacOS/SayKuku") "
    if [[ "$ARCHS" != *" arm64 "* || "$ARCHS" != *" x86_64 "* ]]; then
        print -u2 "Release binary must contain arm64 and x86_64, got:$ARCHS"
        exit 1
    fi
fi
cp -R "$PRODUCT_DIR/SayKuku_SayKuku.bundle" "$APP_DIR/Contents/Resources/SayKuku_SayKuku.bundle"
cp "$ROOT_DIR/Scripts/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$APP_DIR/Contents/Info.plist"
if [[ "$CONFIGURATION" != "release" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName SayKuku Dev" "$APP_DIR/Contents/Info.plist"
fi
cp "$ROOT_DIR/Scripts/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp -R "$ROOT_DIR/Scripts/Resources/en.lproj" "$APP_DIR/Contents/Resources/en.lproj"
cp -R "$ROOT_DIR/Scripts/Resources/zh-Hans.lproj" "$APP_DIR/Contents/Resources/zh-Hans.lproj"

# Keychain ACLs and TCC permissions survive updates only when the app keeps a
# stable, anchored signing identity. Release builds must use Developer ID;
# development builds prefer a local Apple Development certificate.
SIGNING_IDENTITY="${SAYKUKU_SIGNING_IDENTITY:-}"
SIGNING_KEYCHAIN="${SAYKUKU_KEYCHAIN:-}"
if [[ "$CONFIGURATION" == "release" ]]; then
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        print -u2 "Release builds require SAYKUKU_SIGNING_IDENTITY='Developer ID Application: ...'"
        exit 1
    fi
    if [[ "$SIGNING_IDENTITY" != "Developer ID Application: "* ]]; then
        print -u2 "Release builds require a Developer ID Application identity"
        exit 1
    fi
elif [[ -z "$SIGNING_IDENTITY" ]]; then
    VALID_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    USER_HINT="$(id -un)"
    SIGNING_IDENTITY="$(print -r -- "$VALID_IDENTITIES" | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | grep -i "$USER_HINT" | head -n 1 || true)"
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        SIGNING_IDENTITY="$(print -r -- "$VALID_IDENTITIES" | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1)"
    fi
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
    print -u2 "No stable code-signing identity found; set SAYKUKU_SIGNING_IDENTITY explicitly"
    exit 1
fi

IDENTITY_ARGS=(security find-identity -v -p codesigning)
if [[ -n "$SIGNING_KEYCHAIN" ]]; then
    IDENTITY_ARGS+=("$SIGNING_KEYCHAIN")
fi
if ! "${IDENTITY_ARGS[@]}" 2>/dev/null | grep -Fq "\"$SIGNING_IDENTITY\""; then
    print -u2 "Code-signing identity not found: $SIGNING_IDENTITY"
    exit 1
fi

print -u2 "Signing with $SIGNING_IDENTITY"
# Debug builds also run hardened so missing entitlements surface before release.
# They add get-task-allow so debuggers can still attach; notarization rejects it.
ENTITLEMENTS="$ROOT_DIR/Scripts/Resources/SayKuku.entitlements"
if [[ "$CONFIGURATION" == "release" ]]; then
    TIMESTAMP_ARG=--timestamp
else
    TIMESTAMP_ARG=--timestamp=none
    DEBUG_ENTITLEMENTS="$ROOT_DIR/Build/SayKuku.debug.entitlements"
    cp "$ENTITLEMENTS" "$DEBUG_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.get-task-allow bool true" "$DEBUG_ENTITLEMENTS"
    ENTITLEMENTS="$DEBUG_ENTITLEMENTS"
fi
CODESIGN_ARGS=(
    --force --options runtime "$TIMESTAMP_ARG"
    --entitlements "$ENTITLEMENTS"
)
if [[ -n "$SIGNING_KEYCHAIN" ]]; then
    CODESIGN_ARGS+=(--keychain "$SIGNING_KEYCHAIN")
fi
CODESIGN_ARGS+=(--sign "$SIGNING_IDENTITY" "$APP_DIR")
codesign "${CODESIGN_ARGS[@]}" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
print "$APP_DIR"
