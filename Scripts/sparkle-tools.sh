# Pin the signing tools to the same release as Package.swift.
resolve_sparkle_tools() {
    local root="$1"
    local destination="${SAYKUKU_SPARKLE_TOOLS_DIR:-$root/Build/sparkle-tools-2.10.0}"
    if [[ ! -x "$destination/bin/generate_appcast" ]]; then
        local archive="$root/Build/Sparkle-2.10.0-tools.tar.xz"
        mkdir -p "$destination"
        curl --fail --location --silent --show-error \
            https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz -o "$archive" || return 1
        local digest="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
        if [[ "$digest" != c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c ]]; then
            print -u2 "Sparkle tools checksum mismatch"
            return 1
        fi
        tar -xf "$archive" -C "$destination" || return 1
        rm "$archive"
    fi
    print -r -- "$destination/bin"
}
