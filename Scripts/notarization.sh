# Sourced by release.sh and make-dmg.sh. Callers set ROOT_DIR and NOTARY_PROFILE.

# Submit FILE to Apple and require an Accepted result.
notarize() {
    local file="$1"
    local result="${2:-$ROOT_DIR/Build/notarization-${file:t:r}.json}"
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

# Staple FILE and require Gatekeeper to recognize its notarized signature.
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
