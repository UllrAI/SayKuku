#!/bin/zsh
set -euo pipefail

# Internal release step: build a signed, notarized DMG from a notarized App:
#   Scripts/make-dmg.sh <App bundle> <output .dmg>
# Finder lays out the window, so the first run asks once to let the terminal
# control Finder. The output appears only after all release checks pass.

ROOT_DIR="${0:A:h:h}"
NOTARY_PROFILE="SayKuku-Notary"
APP_PATH="${1:?usage: make-dmg.sh <App bundle> <output .dmg>}"
OUTPUT="${2:?usage: make-dmg.sh <App bundle> <output .dmg>}"
APP_PATH="${APP_PATH:A}"
OUTPUT="${OUTPUT:A}"
VOLUME_NAME="SayKuku"
APP_NAME="${APP_PATH:t}"
BACKGROUND_DIR="$ROOT_DIR/Scripts/Resources/DMG"

# Window and icon geometry must match background.png (660x400 points).
WINDOW_WIDTH=660
WINDOW_HEIGHT=400
TITLE_BAR_HEIGHT=28
ICON_SIZE=128
APP_ICON_POSITION="180, 190"
APPLICATIONS_POSITION="480, 190"

fail() {
    print -u2 -r -- "$*"
    exit 1
}

[[ -d "$APP_PATH" ]] || fail "App bundle not found: $APP_PATH"
[[ "$OUTPUT" == *.dmg ]] || fail "Output must be a .dmg file: $OUTPUT"
[[ ! -e "$OUTPUT" ]] || fail "Output already exists: $OUTPUT"
# Finder addresses the volume by name, so another mounted SayKuku would be ambiguous.
[[ ! -e "/Volumes/$VOLUME_NAME" ]] || fail "/Volumes/$VOLUME_NAME is already mounted; eject it first"

source "$ROOT_DIR/Scripts/signing-identity.sh"
source "$ROOT_DIR/Scripts/notarization.sh"
SIGNING_IDENTITY="$(resolve_signing_identity release)"
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null; then
    fail "notarytool profile $NOTARY_PROFILE is unavailable; see docs/LOCAL_PACKAGING.md section 1"
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
xcrun stapler validate "$APP_PATH"
APP_ASSESSMENT="$(spctl --assess --type execute --verbose=4 "$APP_PATH" 2>&1)" || fail "Gatekeeper did not accept the App: $APP_ASSESSMENT"
[[ "$APP_ASSESSMENT" == *"source=Notarized Developer ID"* ]] || fail "App is not notarized: $APP_ASSESSMENT"

mkdir -p "${OUTPUT:h}"
WORK_DIR="$(mktemp -d "${OUTPUT:h}/.saykuku-dmg.XXXXXX")"
STAGE_DIR="$WORK_DIR/stage"
RW_IMAGE="$WORK_DIR/rw.dmg"
PENDING_DMG="$WORK_DIR/${OUTPUT:t}"
DEVICE=""
cleanup() {
    if [[ -n "$DEVICE" ]]; then
        hdiutil detach -quiet "$DEVICE" || hdiutil detach -quiet -force "$DEVICE" || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGE_DIR/.background"
ditto "$APP_PATH" "$STAGE_DIR/$APP_NAME"
ln -s /Applications "$STAGE_DIR/Applications"
# One TIFF with both resolutions so Retina displays get the @2x image.
tiffutil -cathidpicheck "$BACKGROUND_DIR/background.png" "$BACKGROUND_DIR/background@2x.png" \
    -out "$STAGE_DIR/.background/background.tiff" >/dev/null

# Leave headroom for the .DS_Store Finder writes into the image.
SIZE_MB=$(( $(du -sm "$STAGE_DIR" | cut -f 1) + 20 ))
hdiutil create -quiet -srcfolder "$STAGE_DIR" -volname "$VOLUME_NAME" -fs HFS+ \
    -format UDRW -size "${SIZE_MB}m" "$RW_IMAGE"
DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_IMAGE" | awk 'NR == 1 { print $1 }')"
MOUNT_DIR="/Volumes/$VOLUME_NAME"
detach() {
    hdiutil detach -quiet "$DEVICE" || { sleep 2; hdiutil detach -quiet -force "$DEVICE"; }
}
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, $(( 200 + WINDOW_WIDTH )), $(( 120 + WINDOW_HEIGHT + TITLE_BAR_HEIGHT ))}
        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to $ICON_SIZE
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "$APP_NAME" of container window to {$APP_ICON_POSITION}
        set position of item "Applications" of container window to {$APPLICATIONS_POSITION}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Finder writes .DS_Store asynchronously; without it the layout is lost.
for _ in {1..10}; do
    [[ -f "$MOUNT_DIR/.DS_Store" ]] && break
    sleep 1
done
[[ -f "$MOUNT_DIR/.DS_Store" ]] || fail "Finder did not save the window layout into the DMG"
rm -rf "$MOUNT_DIR/.fseventsd"
sync
detach
DEVICE=""

hdiutil convert -quiet "$RW_IMAGE" -format ULFO -o "$PENDING_DMG"
CODESIGN_ARGS=(--sign "$SIGNING_IDENTITY" --timestamp)
if [[ -n "${SAYKUKU_KEYCHAIN:-}" ]]; then
    CODESIGN_ARGS+=(--keychain "$SAYKUKU_KEYCHAIN")
fi
codesign "${CODESIGN_ARGS[@]}" "$PENDING_DMG"
codesign --verify --strict --verbose=2 "$PENDING_DMG"
notarize "$PENDING_DMG" "$ROOT_DIR/Build/notarization-${OUTPUT:t:r}.json"
staple_and_assess "$PENDING_DMG" --type open --context context:primary-signature
hdiutil verify -quiet "$PENDING_DMG"
[[ ! -e "$OUTPUT" ]] || fail "Output appeared during DMG creation: $OUTPUT"
rm "$ROOT_DIR/Build/notarization-${OUTPUT:t:r}.json"
mv "$PENDING_DMG" "$OUTPUT"
print -r -- "$OUTPUT"
