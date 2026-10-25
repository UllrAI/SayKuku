#!/bin/zsh
set -euo pipefail

# Build and verify a release, then publish the package, website and feeds.
# --resume reuses a verified archive after a publication failure; --prepare stays local.

ROOT_DIR="${0:A:h:h}"
NOTARY_PROFILE="SayKuku-Notary"
APP_DIR="$ROOT_DIR/Build/SayKuku.app"
DIST_DIR="$ROOT_DIR/Dist"
VERSION_FEED="$DIST_DIR/ver.json"

fail() {
    print -u2 -r -- "$*"
    exit 1
}
source "$ROOT_DIR/Scripts/notarization.sh"

source "$ROOT_DIR/Scripts/sparkle-tools.sh"
SPARKLE_TOOLS="$(resolve_sparkle_tools "$ROOT_DIR")"
MODE=publish
NOTES_FILE=""
RESUME_FILE=""
while (( $# )); do
    case "$1" in
        --prepare) MODE=prepare; shift ;;
        --notes) NOTES_FILE="${2:?Supply release notes}"; shift 2 ;;
        --resume) RESUME_FILE="${2:?Supply Dist/releases/VERSION/release.json}"; shift 2 ;;
        *) fail "Usage: Scripts/release.sh [--prepare] --notes FILE | --resume RELEASE_JSON" ;;
    esac
done
[[ -z "$RESUME_FILE" || -z "$NOTES_FILE" ]] || fail "--resume cannot be combined with --notes"

cd "$ROOT_DIR"

# 1. Preflight: everything that can be checked before spending time on a build.
if [[ -n "$(git status --porcelain)" ]]; then
    fail "Working tree must be clean before a release; commit or remove local changes first"
fi
if [[ "$MODE" == "publish" && "$(git branch --show-current)" != main ]]; then
    fail "Publish from main; --prepare can build a local candidate on another committed branch"
fi
if [[ -n "$RESUME_FILE" ]]; then
    RESUME_COMMAND=publish
    [[ "$MODE" == prepare ]] && RESUME_COMMAND=complete
    python3 "$ROOT_DIR/Scripts/release.py" "$RESUME_COMMAND" "$RESUME_FILE" --tools "$SPARKLE_TOOLS"
    exit
fi
[[ -f "$NOTES_FILE" ]] || fail "Provide --notes FILE with this release's changes"
# Resolve once and hand the result to package-app.sh so both use the same identity.
source "$ROOT_DIR/Scripts/signing-identity.sh"
SAYKUKU_SIGNING_IDENTITY="$(resolve_signing_identity release)"
export SAYKUKU_SIGNING_IDENTITY
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Scripts/Resources/Info.plist")"
[[ ! -f "$DIST_DIR/releases/$VERSION/release.json" ]] || fail "Prepared release exists; use --resume or preserve it before rebuilding"
TAG="v${VERSION}"
COMMIT="$(git rev-parse HEAD)"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    fail "Tag $TAG already exists; bump CFBundleShortVersionString in Scripts/Resources/Info.plist first"
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null; then
    fail "notarytool profile $NOTARY_PROFILE is unavailable; see docs/LOCAL_PACKAGING.md section 1"
fi
# make-dmg.sh refuses to run then; catch it before the first notarization.
if [[ -e /Volumes/SayKuku ]]; then
    fail "/Volumes/SayKuku is mounted; eject it before releasing"
fi

PUBLIC_KEY="$("$SPARKLE_TOOLS/generate_keys" --account com.saykuku.app -p)"
EXPECTED_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT_DIR/Scripts/Resources/Info.plist")"
[[ "$PUBLIC_KEY" == "$EXPECTED_KEY" ]] || fail "Sparkle signing key does not match the App public key"
if [[ "$MODE" == "publish" ]]; then
    python3 "$ROOT_DIR/Scripts/release.py" preflight "$VERSION" "$(git rev-list --count HEAD)"
fi
swift test

# Keep earlier artifacts of the same version instead of overwriting them.
NOTARY_ARCHIVE="$DIST_DIR/SayKuku-${VERSION}-notarization.zip"
DMG="$DIST_DIR/SayKuku-${VERSION}.dmg"
DSYM_DIR="$DIST_DIR/SayKuku-${VERSION}.dSYM"
SPARKLE_DSYM_DIR="$DIST_DIR/SayKuku-${VERSION}-Sparkle.dSYMs"
mkdir -p "$DIST_DIR"
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"
for ARTIFACT in "$NOTARY_ARCHIVE" "$DMG" "$DSYM_DIR" "$SPARKLE_DSYM_DIR"; do
    if [[ -e "$ARTIFACT" ]]; then
        mv "$ARTIFACT" "${ARTIFACT:r}-backup-${BACKUP_SUFFIX}.${ARTIFACT:e}"
    fi
done

# 2. Signed universal App plus dSYM.
"$ROOT_DIR/Scripts/package-app.sh" release
# Read the build number from the packaged App so the summary shows what shipped.
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DIR/Contents/Info.plist")"
if [[ ! -d "$DSYM_DIR" ]]; then
    fail "Expected dSYM was not produced: $DSYM_DIR"
fi

# 3. Notarize and staple the App first, so the copy users drag out of the DMG
# carries its own ticket. The ZIP uploaded to Apple is never shipped.
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$APP_DIR" "$NOTARY_ARCHIVE"
unzip -tq "$NOTARY_ARCHIVE"
notarize "$NOTARY_ARCHIVE"
staple_and_assess "$APP_DIR" --type execute

# 4. Publish the DMG only after its own signature, notarization and checks pass.
"$ROOT_DIR/Scripts/make-dmg.sh" "$APP_DIR" "$DMG" >/dev/null
SHA256="$(shasum -a 256 "$DMG" | cut -d ' ' -f 1)"

# The App upload ZIP and notarization receipt are useful only while diagnosing
# a failed release. Keep the stapled App, DMG and matching dSYM.
rm "$NOTARY_ARCHIVE" "$ROOT_DIR/Build/notarization-${NOTARY_ARCHIVE:t:r}.json"

# 5. Sign only the final stapled DMG. One metadata file drives every public surface.
python3 "$ROOT_DIR/Scripts/release.py" prepare --dmg "$DMG" --app "$APP_DIR" \
    --notes "$NOTES_FILE" --tools "$SPARKLE_TOOLS" --commit "$COMMIT"
RELEASE_METADATA="$DIST_DIR/releases/$VERSION/release.json"
if [[ "$MODE" == "publish" ]]; then
    python3 "$ROOT_DIR/Scripts/release.py" publish "$RELEASE_METADATA" --tools "$SPARKLE_TOOLS"
else
    print -u2 "Prepared and verified release: $RELEASE_METADATA"
    print -u2 "After review, publish from main with Scripts/release.sh --resume $RELEASE_METADATA"
fi
print "$DMG"
