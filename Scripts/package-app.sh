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

# Keychain ACLs and TCC permissions survive updates only when the app keeps a
# stable, anchored signing identity. Resolve it before building so a missing
# certificate fails in seconds rather than after a universal build.
source "$ROOT_DIR/Scripts/signing-identity.sh"
SIGNING_IDENTITY="$(resolve_signing_identity "$CONFIGURATION")"
SIGNING_KEYCHAIN="${SAYKUKU_KEYCHAIN:-}"

# Theme.swift calls glassEffect behind #available(macOS 26.0, *), which only
# compiles against the macOS 26 SDK. Fail here instead of deep in swift build.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if (( ${SDK_VERSION%%.*} < 26 )); then
    print -u2 "SayKuku needs the macOS 26 SDK (Xcode 26 or newer); found macOS SDK $SDK_VERSION"
    exit 1
fi

# Derive CFBundleVersion from the commit count: it grows with main and stays
# the same when one commit is rebuilt.
if [[ "$(git -C "$ROOT_DIR" rev-parse --is-shallow-repository)" == "true" ]]; then
    print -u2 "Shallow clone: the commit count would understate CFBundleVersion; run git fetch --unshallow"
    exit 1
fi
BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD)" || {
    print -u2 "Could not count commits for CFBundleVersion; package from a Git checkout"
    exit 1
}

BUILD_ARGS=(-c "$CONFIGURATION")
# macOS 15 still runs on Intel, so release builds ship a universal binary.
if [[ "$CONFIGURATION" == "release" ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

cd "$ROOT_DIR"
swift build "${BUILD_ARGS[@]}"

PRODUCT_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP_DIR="$ROOT_DIR/Build/SayKuku.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

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
    # Crash reports only symbolicate against a dSYM whose UUIDs match the binary.
    BINARY_UUIDS="$(dwarfdump --uuid "$APP_BINARY" | awk '{ print $2, $3 }' | sort)"
    DSYM_UUIDS="$(dwarfdump --uuid "$DSYM_DIR" | awk '{ print $2, $3 }' | sort)"
    if [[ -z "$BINARY_UUIDS" || "$BINARY_UUIDS" != "$DSYM_UUIDS" ]]; then
        print -u2 "dSYM UUIDs do not match the App binary:"
        print -u2 -r -l -- "binary: $BINARY_UUIDS" "dSYM:   $DSYM_UUIDS"
        exit 1
    fi
fi
cp -R "$PRODUCT_DIR/SayKuku_SayKuku.bundle" "$APP_DIR/Contents/Resources/SayKuku_SayKuku.bundle"
cp "$ROOT_DIR/Scripts/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
if [[ "$CONFIGURATION" != "release" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName SayKuku Dev" "$APP_DIR/Contents/Info.plist"
fi
cp "$ROOT_DIR/Scripts/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
# macOS 26 draws the layered Icon Composer icon from Assets.car via
# CFBundleIconName; older systems keep AppIcon.icns via CFBundleIconFile.
# A missing or failing actool only costs the layered icon, never the package.
ICON_SOURCE="$ROOT_DIR/Scripts/Resources/AppIcon.icon"
if [[ -d "$ICON_SOURCE" ]]; then
    ICON_WORK_DIR="$ROOT_DIR/Build/AppIcon.actool"
    ICON_PARTIAL_PLIST="$ICON_WORK_DIR/assetcatalog_generated_info.plist"
    rm -rf "$ICON_WORK_DIR"
    mkdir -p "$ICON_WORK_DIR"
    # The .icon basename must match --app-icon. Target macOS 26 so actool
    # does not bake legacy renditions that would replace AppIcon.icns on 15.
    if xcrun actool "$ICON_SOURCE" --compile "$ICON_WORK_DIR" \
            --output-format human-readable-text --notices --warnings --errors \
            --output-partial-info-plist "$ICON_PARTIAL_PLIST" \
            --app-icon AppIcon --include-all-app-icons \
            --enable-on-demand-resources NO --development-region en \
            --target-device mac --platform macosx --minimum-deployment-target 26.0 \
            >"$ICON_WORK_DIR/actool.log" 2>&1 \
        && [[ -f "$ICON_WORK_DIR/Assets.car" ]] \
        && [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$ICON_PARTIAL_PLIST" 2>/dev/null)" == "AppIcon" ]]; then
        cp "$ICON_WORK_DIR/Assets.car" "$APP_DIR/Contents/Resources/Assets.car"
        /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP_DIR/Contents/Info.plist"
    else
        print -u2 "warning: actool could not compile AppIcon.icon (see $ICON_WORK_DIR/actool.log); shipping AppIcon.icns only"
    fi
fi
cp -R "$ROOT_DIR/Scripts/Resources/en.lproj" "$APP_DIR/Contents/Resources/en.lproj"
cp -R "$ROOT_DIR/Scripts/Resources/zh-Hans.lproj" "$APP_DIR/Contents/Resources/zh-Hans.lproj"
# Third-party license notices ship inside the App.
cp -R "$ROOT_DIR/Scripts/Resources/Licenses" "$APP_DIR/Contents/Resources/Licenses"

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
codesign "${CODESIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" "$APP_DIR" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
print "$APP_DIR"
