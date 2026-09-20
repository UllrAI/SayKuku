#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-debug}"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

PRODUCT_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$ROOT_DIR/Build/SayKuku.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$PRODUCT_DIR/SayKuku" "$APP_DIR/Contents/MacOS/SayKuku"
cp -R "$PRODUCT_DIR/SayKuku_SayKuku.bundle" "$APP_DIR/Contents/Resources/SayKuku_SayKuku.bundle"
cp "$ROOT_DIR/Scripts/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Scripts/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp -R "$ROOT_DIR/Scripts/Resources/en.lproj" "$APP_DIR/Contents/Resources/en.lproj"
cp -R "$ROOT_DIR/Scripts/Resources/zh-Hans.lproj" "$APP_DIR/Contents/Resources/zh-Hans.lproj"

# TCC permissions survive rebuilds only when the app has a stable, anchored
# signing identity. Prefer an explicit identity, then a local Apple Development
# certificate. Ad-hoc signing remains a fallback for machines without one.
SIGNING_IDENTITY="${SAYKUKU_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    VALID_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    USER_HINT="$(id -un)"
    SIGNING_IDENTITY="$(print -r -- "$VALID_IDENTITIES" | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | grep -i "$USER_HINT" | head -n 1 || true)"
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        SIGNING_IDENTITY="$(print -r -- "$VALID_IDENTITIES" | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1)"
    fi
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
    print -u2 "Signing with $SIGNING_IDENTITY"
    codesign --force --deep --sign "$SIGNING_IDENTITY" --timestamp=none "$APP_DIR" >/dev/null
else
    print -u2 "Warning: no development certificate found; TCC permissions may reset after rebuilds"
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi
print "$APP_DIR"
