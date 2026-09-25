# Sourced by package-app.sh and release.sh; not meant to be run directly.
#
# resolve_signing_identity CONFIGURATION prints the code-signing identity to use.
# SAYKUKU_SIGNING_IDENTITY wins when set. Otherwise release picks the only
# Developer ID Application identity and fails when there is none or several;
# development prefers an Apple Development identity naming the current user.
# SAYKUKU_KEYCHAIN limits the search to one keychain.
resolve_signing_identity() {
    setopt local_options extended_glob
    local configuration="$1"
    local list_args=(security find-identity -v -p codesigning)
    if [[ -n "${SAYKUKU_KEYCHAIN:-}" ]]; then
        list_args+=("$SAYKUKU_KEYCHAIN")
    fi
    local -a identities
    identities=("${(@f)$("${list_args[@]}" 2>/dev/null | sed -n 's/.*"\(.*\)".*/\1/p' | sort -u)}")
    identities=(${identities:#})
    local -a candidates

    local identity="${SAYKUKU_SIGNING_IDENTITY:-}"
    if [[ -n "$identity" ]]; then
        if [[ "$configuration" == "release" && "$identity" != "Developer ID Application: "* ]]; then
            print -u2 "Release builds require a Developer ID Application identity, got: $identity"
            return 1
        fi
        if (( ! ${identities[(Ie)$identity]} )); then
            print -u2 "Code-signing identity not found: $identity"
            return 1
        fi
        print -r -- "$identity"
        return
    fi

    if [[ "$configuration" == "release" ]]; then
        candidates=(${(M)identities:#Developer ID Application: *})
        if (( ${#candidates} == 1 )); then
            print -r -- "$candidates[1]"
            return
        fi
        if (( ${#candidates} == 0 )); then
            print -u2 "No Developer ID Application identity with a private key was found; see docs/LOCAL_PACKAGING.md section 1"
        else
            print -u2 "Several Developer ID Application identities were found; pick one with SAYKUKU_SIGNING_IDENTITY:"
            print -u2 -l -- "  "${^candidates}
        fi
        return 1
    fi

    candidates=(${(M)identities:#Apple Development: *})
    local -a own=(${(M)candidates:#(#i)*${(b)$(id -un)}*})
    identity="${own[1]:-${candidates[1]:-}}"
    if [[ -z "$identity" ]]; then
        print -u2 "No stable code-signing identity found; set SAYKUKU_SIGNING_IDENTITY explicitly"
        return 1
    fi
    print -r -- "$identity"
}
