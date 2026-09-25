#!/bin/zsh
set -euo pipefail

# Build, notarize, staple and archive a release, then write its ver.json. Fails
# fast on the first error; nothing is retried and nothing prompts.
# See docs/LOCAL_PACKAGING.md.

ROOT_DIR="${0:A:h:h}"
NOTARY_PROFILE="SayKuku-Notary"
APP_DIR="$ROOT_DIR/Build/SayKuku.app"
DIST_DIR="$ROOT_DIR/Dist"
VERSION_FEED="$DIST_DIR/ver.json"
NOTARY_RESULT="$ROOT_DIR/Build/notarization-result.json"

fail() {
    print -u2 -r -- "$*"
    exit 1
}

cd "$ROOT_DIR"

# 1. Preflight: everything that can be checked before spending time on a build.
if [[ -n "$(git status --porcelain)" ]]; then
    fail "Working tree must be clean before a release; commit or remove local changes first"
fi
if [[ -z "${SAYKUKU_SIGNING_IDENTITY:-}" ]]; then
    fail "Release requires SAYKUKU_SIGNING_IDENTITY='Developer ID Application: ...'"
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Scripts/Resources/Info.plist")"
TAG="v${VERSION}"
COMMIT="$(git rev-parse HEAD)"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    fail "Tag $TAG already exists; bump CFBundleShortVersionString in Scripts/Resources/Info.plist first"
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null; then
    fail "notarytool profile $NOTARY_PROFILE is unavailable; see docs/LOCAL_PACKAGING.md section 1"
fi

swift test

# Keep earlier artifacts of the same version instead of overwriting them.
NOTARY_ARCHIVE="$DIST_DIR/SayKuku-${VERSION}-notarization.zip"
FINAL_ARCHIVE="$DIST_DIR/SayKuku-${VERSION}.zip"
DSYM_DIR="$DIST_DIR/SayKuku-${VERSION}.dSYM"
mkdir -p "$DIST_DIR"
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"
for ARTIFACT in "$NOTARY_ARCHIVE" "$FINAL_ARCHIVE" "$DSYM_DIR"; do
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

# 3. Notarize. The archive uploaded to Apple is never shipped to users.
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$APP_DIR" "$NOTARY_ARCHIVE"
unzip -tq "$NOTARY_ARCHIVE"
print -u2 "Submitting $NOTARY_ARCHIVE for notarization; this usually takes a few minutes"
SUBMIT_STATUS=0
xcrun notarytool submit "$NOTARY_ARCHIVE" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --timeout 30m \
    --output-format json >"$NOTARY_RESULT" || SUBMIT_STATUS=$?
SUBMISSION_ID="$(plutil -extract id raw -o - "$NOTARY_RESULT" 2>/dev/null || true)"
NOTARY_STATUS="$(plutil -extract status raw -o - "$NOTARY_RESULT" 2>/dev/null || true)"
if (( SUBMIT_STATUS != 0 )) || [[ "$NOTARY_STATUS" != "Accepted" ]]; then
    print -u2 "Notarization failed (status: ${NOTARY_STATUS:-unknown}, exit code: $SUBMIT_STATUS)"
    cat "$NOTARY_RESULT" >&2
    if [[ -n "$SUBMISSION_ID" ]]; then
        xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fi
    exit 1
fi
print -u2 "Notarization accepted: $SUBMISSION_ID"

# 4. Staple the ticket and make sure Gatekeeper sees a notarized App.
xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
SPCTL_STATUS=0
SPCTL_OUTPUT="$(spctl --assess --type execute --verbose=4 "$APP_DIR" 2>&1)" || SPCTL_STATUS=$?
print -u2 -r -- "$SPCTL_OUTPUT"
if (( SPCTL_STATUS != 0 )) || [[ "$SPCTL_OUTPUT" != *"source=Notarized Developer ID"* ]]; then
    fail "Gatekeeper did not accept the App as Notarized Developer ID"
fi

# 5. The shipped archive must be rebuilt from the stapled App.
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$APP_DIR" "$FINAL_ARCHIVE"
unzip -tq "$FINAL_ARCHIVE"
if unzip -Z1 "$FINAL_ARCHIVE" | grep -E '(^|/)\._' >/dev/null; then
    fail "$FINAL_ARCHIVE contains AppleDouble metadata"
fi
SHA256="$(shasum -a 256 "$FINAL_ARCHIVE" | cut -d ' ' -f 1)"

# 6. The version file installed apps read. Fill in notes by hand before uploading.
cat >"$VERSION_FEED" <<EOF
{
  "version": "$VERSION",
  "url": "https://github.com/UllrAI/SayKuku/releases/tag/$TAG",
  "notes": ""
}
EOF

# 7. Tag the commit that was built. Pushing stays a manual decision.
git tag "$TAG" "$COMMIT"

print -u2 ""
print -u2 "Released SayKuku $VERSION ($TAG -> ${COMMIT[1,12]})"
print -u2 "  Build:   $BUILD_NUMBER"
print -u2 "  Archive: $FINAL_ARCHIVE"
print -u2 "  SHA-256: $SHA256"
print -u2 "  dSYM:    $DSYM_DIR"
print -u2 "  Feed:    $VERSION_FEED"
print -u2 "Publish with: git push origin $TAG && gh release create $TAG $FINAL_ARCHIVE"
print -u2 "Then upload $VERSION_FEED to https://saykuku.ullrai.com/ver.json"
print "$FINAL_ARCHIVE"
