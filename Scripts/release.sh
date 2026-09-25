#!/bin/zsh
set -euo pipefail

# Build, notarize and staple the App, wrap it in a drag-to-install DMG, then
# sign, notarize and staple the DMG and write ver.json. Fails fast on the first
# error; nothing is retried and nothing prompts. See docs/LOCAL_PACKAGING.md.

ROOT_DIR="${0:A:h:h}"
NOTARY_PROFILE="SayKuku-Notary"
APP_DIR="$ROOT_DIR/Build/SayKuku.app"
DIST_DIR="$ROOT_DIR/Dist"
VERSION_FEED="$DIST_DIR/ver.json"

fail() {
    print -u2 -r -- "$*"
    exit 1
}

# notarize FILE: submit to Apple and wait; prints the log and exits unless Accepted.
notarize() {
    local file="$1"
    local result="$ROOT_DIR/Build/notarization-${file:t:r}.json"
    local submit_status=0
    print -u2 "Submitting ${file:t} for notarization; this usually takes a few minutes"
    xcrun notarytool submit "$file" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        --timeout 30m \
        --output-format json >"$result" || submit_status=$?
    local submission_id="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
    local notary_status="$(plutil -extract status raw -o - "$result" 2>/dev/null || true)"
    if (( submit_status != 0 )) || [[ "$notary_status" != "Accepted" ]]; then
        print -u2 "Notarization of ${file:t} failed (status: ${notary_status:-unknown}, exit code: $submit_status)"
        cat "$result" >&2
        if [[ -n "$submission_id" ]]; then
            xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
        fi
        exit 1
    fi
    print -u2 "Notarization of ${file:t} accepted: $submission_id"
}

# staple_and_assess FILE SPCTL_ARGS...: staple the ticket, then require Gatekeeper
# to report a notarized Developer ID signature.
staple_and_assess() {
    local file="$1"
    shift
    xcrun stapler staple "$file"
    xcrun stapler validate "$file"
    local spctl_status=0
    local spctl_output
    spctl_output="$(spctl --assess "$@" --verbose=4 "$file" 2>&1)" || spctl_status=$?
    print -u2 -r -- "$spctl_output"
    if (( spctl_status != 0 )) || [[ "$spctl_output" != *"source=Notarized Developer ID"* ]]; then
        fail "Gatekeeper did not accept ${file:t} as Notarized Developer ID"
    fi
}

cd "$ROOT_DIR"

# 1. Preflight: everything that can be checked before spending time on a build.
if [[ -n "$(git status --porcelain)" ]]; then
    fail "Working tree must be clean before a release; commit or remove local changes first"
fi
# Resolve once and hand the result to package-app.sh so both use the same identity.
source "$ROOT_DIR/Scripts/signing-identity.sh"
SAYKUKU_SIGNING_IDENTITY="$(resolve_signing_identity release)"
export SAYKUKU_SIGNING_IDENTITY
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Scripts/Resources/Info.plist")"
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

swift test

# Keep earlier artifacts of the same version instead of overwriting them.
NOTARY_ARCHIVE="$DIST_DIR/SayKuku-${VERSION}-notarization.zip"
DMG="$DIST_DIR/SayKuku-${VERSION}.dmg"
DSYM_DIR="$DIST_DIR/SayKuku-${VERSION}.dSYM"
mkdir -p "$DIST_DIR"
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"
for ARTIFACT in "$NOTARY_ARCHIVE" "$DMG" "$DSYM_DIR"; do
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

# 4. Wrap the stapled App in a DMG, then sign, notarize and staple the DMG itself.
"$ROOT_DIR/Scripts/make-dmg.sh" "$APP_DIR" "$DMG" >/dev/null
CODESIGN_ARGS=(--sign "$SAYKUKU_SIGNING_IDENTITY" --timestamp)
if [[ -n "${SAYKUKU_KEYCHAIN:-}" ]]; then
    CODESIGN_ARGS+=(--keychain "$SAYKUKU_KEYCHAIN")
fi
codesign "${CODESIGN_ARGS[@]}" "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
notarize "$DMG"
staple_and_assess "$DMG" --type open --context context:primary-signature
hdiutil verify -quiet "$DMG"
SHA256="$(shasum -a 256 "$DMG" | cut -d ' ' -f 1)"

# 5. The version file installed apps read. Fill in notes by hand before uploading.
cat >"$VERSION_FEED" <<JSON
{
  "version": "$VERSION",
  "url": "https://github.com/UllrAI/SayKuku/releases/tag/$TAG",
  "notes": ""
}
JSON

# 6. Tag the commit that was built. Pushing stays a manual decision.
git tag "$TAG" "$COMMIT"

print -u2 ""
print -u2 "Released SayKuku $VERSION ($TAG -> ${COMMIT[1,12]})"
print -u2 "  Build:   $BUILD_NUMBER"
print -u2 "  DMG:     $DMG"
print -u2 "  SHA-256: $SHA256"
print -u2 "  dSYM:    $DSYM_DIR"
print -u2 "  Feed:    $VERSION_FEED"
print -u2 "Publish with: git push origin $TAG && gh release create $TAG $DMG"
print -u2 "Then upload $VERSION_FEED to https://saykuku.ullrai.com/ver.json"
print "$DMG"
