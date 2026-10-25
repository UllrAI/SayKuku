# Sourced after CODESIGN_ARGS and CONFIGURATION are set by the packaging caller.
sign_sparkle_framework() {
    local SPARKLE_FRAMEWORK="$1"
    local COMPONENT COMPONENT_BINARY COMPONENT_ARCHS
    local SPARKLE_CURRENT="$SPARKLE_FRAMEWORK/Versions/Current"
    for COMPONENT in "$SPARKLE_CURRENT/Autoupdate" "$SPARKLE_CURRENT/Updater.app" "$SPARKLE_CURRENT/XPCServices/"*.xpc; do
        codesign "${CODESIGN_ARGS[@]}" --preserve-metadata=identifier,entitlements "$COMPONENT" >/dev/null
        if [[ "$CONFIGURATION" == "release" ]]; then
            if [[ -d "$COMPONENT" ]]; then
                COMPONENT_BINARY="$COMPONENT/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$COMPONENT/Contents/Info.plist")"
            else
                COMPONENT_BINARY="$COMPONENT"
            fi
            COMPONENT_ARCHS=" $(lipo -archs "$COMPONENT_BINARY") "
            if [[ "$COMPONENT_ARCHS" != *" arm64 "* || "$COMPONENT_ARCHS" != *" x86_64 "* ]]; then
                print -u2 "Sparkle helper is not universal: $COMPONENT"
                exit 1
            fi
        fi
    done
    if [[ "$CONFIGURATION" == release ]]; then
        COMPONENT_ARCHS=" $(lipo -archs "$SPARKLE_CURRENT/Sparkle") "
        if [[ "$COMPONENT_ARCHS" != *" arm64 "* || "$COMPONENT_ARCHS" != *" x86_64 "* ]]; then
            print -u2 "Sparkle framework is not universal"
            exit 1
        fi
    fi
    codesign "${CODESIGN_ARGS[@]}" --preserve-metadata=identifier "$SPARKLE_FRAMEWORK" >/dev/null
}
