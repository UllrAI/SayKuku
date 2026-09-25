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

# Sparkle compares CFBundleVersion, so derive it from the commit count: it grows
# with main and stays the same when one commit is rebuilt.
BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD)" || {
    print -u2 "Could not count commits for CFBundleVersion; package from a Git checkout"
    exit 1
}

# Sparkle.framework lives in Contents/Frameworks, which SwiftPM's default rpath does not cover.
BUILD_ARGS=(-c "$CONFIGURATION" -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
# macOS 15 still runs on Intel, so release builds ship a universal binary.
if [[ "$CONFIGURATION" == "release" ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
    # Sparkle refuses to start without the EdDSA public key; see docs/LOCAL_PACKAGING.md.
    ED_PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT_DIR/Scripts/Resources/Info.plist" 2>/dev/null || true)"
    if [[ -z "$ED_PUBLIC_KEY" ]]; then
        print -u2 "Release builds require SUPublicEDKey in Scripts/Resources/Info.plist"
        exit 1
    fi
fi

cd "$ROOT_DIR"
swift build "${BUILD_ARGS[@]}"

PRODUCT_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP_DIR="$ROOT_DIR/Build/SayKuku.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"

APP_BINARY="$APP_DIR/Contents/MacOS/SayKuku"
if [[ "$CONFIGURATION" == "release" ]]; then
    # Keep the debug symbols in a dSYM so shipped crash reports can be
    # symbolicated, then strip them from the binary that goes into the App.
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Scripts/Resources/Info.plist")"
    DSYM_DIR="$ROOT_DIR/Dist/SayKuku-${VERSION}.dSYM"
    mkdir -p "$ROOT_DIR/Dist"
    rm -rf "$DSYM_DIR"
    DSYMUTIL_STATUS=0
    DSYMUTIL_OUTPUT="$(dsymutil "$PRODUCT_DIR/SayKuku" -o "$DSYM_DIR" 2>&1)" || DSYMUTIL_STATUS=$?
    if [[ -n "$DSYMUTIL_OUTPUT" ]]; then
        print -u2 -r -- "$DSYMUTIL_OUTPUT"
    fi
    if (( DSYMUTIL_STATUS != 0 )) || [[ "$DSYMUTIL_OUTPUT" == *"no debug symbols"* ]]; then
        print -u2 "dsymutil could not extract debug symbols into $DSYM_DIR"
        exit 1
    fi
fi
cp "$PRODUCT_DIR/SayKuku" "$APP_BINARY"
if [[ "$CONFIGURATION" == "release" ]]; then
    # strip -S keeps every architecture; the lipo check below runs on the result.
    strip -S "$APP_BINARY"
    ARCHS=" $(lipo -archs "$APP_BINARY") "
    if [[ "$ARCHS" != *" arm64 "* || "$ARCHS" != *" x86_64 "* ]]; then
        print -u2 "Release binary must contain arm64 and x86_64, got:$ARCHS"
        exit 1
    fi
fi
cp -R "$PRODUCT_DIR/SayKuku_SayKuku.bundle" "$APP_DIR/Contents/Resources/SayKuku_SayKuku.bundle"
SPARKLE_FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
# ditto keeps the framework's Versions symlinks intact.
ditto "$PRODUCT_DIR/Sparkle.framework" "$SPARKLE_FRAMEWORK"
cp "$ROOT_DIR/Scripts/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
if [[ "$CONFIGURATION" != "release" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName SayKuku Dev" "$APP_DIR/Contents/Info.plist"
fi
cp "$ROOT_DIR/Scripts/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp -R "$ROOT_DIR/Scripts/Resources/en.lproj" "$APP_DIR/Contents/Resources/en.lproj"
cp -R "$ROOT_DIR/Scripts/Resources/zh-Hans.lproj" "$APP_DIR/Contents/Resources/zh-Hans.lproj"
# Redistributing Sparkle's binaries requires shipping its license notices.
cp -R "$ROOT_DIR/Scripts/Resources/Licenses" "$APP_DIR/Contents/Resources/Licenses"

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
CODESIGN_ARGS=(--force --options runtime "$TIMESTAMP_ARG" --sign "$SIGNING_IDENTITY")
if [[ -n "$SIGNING_KEYCHAIN" ]]; then
    CODESIGN_ARGS+=(--keychain "$SIGNING_KEYCHAIN")
fi
# Sign inside out without --deep: Sparkle's helpers keep their own entitlements
# (Downloader.xpc has one) and must never receive the App's.
SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/B"
for NESTED_CODE in "$SPARKLE_VERSION_DIR"/XPCServices/*.xpc "$SPARKLE_VERSION_DIR/Autoupdate" "$SPARKLE_VERSION_DIR/Updater.app"; do
    codesign "${CODESIGN_ARGS[@]}" --preserve-metadata=entitlements "$NESTED_CODE" >/dev/null
done
codesign "${CODESIGN_ARGS[@]}" "$SPARKLE_FRAMEWORK" >/dev/null
codesign "${CODESIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" "$APP_DIR" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
print "$APP_DIR"
