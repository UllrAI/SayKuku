#!/bin/zsh
set -euo pipefail

# Speak each mixed-language fixture sentence with say, then run the live eval
# on the recordings. Audio is cached in Build/eval-audio so runs before and
# after a prompt change hear the same sound. See docs/MIXED_LANGUAGE_EVAL.md.

ROOT_DIR="${0:A:h:h}"
FIXTURE="$ROOT_DIR/Tests/SayKukuTests/Fixtures/mixed-language.json"
AUDIO_DIR="$ROOT_DIR/Build/eval-audio"

fail() {
    print -u2 -r -- "$*"
    exit 1
}

# Tingting when installed, otherwise the first Mandarin voice on this Mac.
VOICE=""
for line in "${(@f)$(say -v '?')}"; do
    if [[ "$line" =~ '^(.*[^ ]) +zh_CN +#' ]]; then
        if [[ "$match[1]" == Tingting* ]]; then
            VOICE="$match[1]"
            break
        fi
        if [[ -z "$VOICE" ]]; then
            VOICE="$match[1]"
        fi
    fi
done
[[ -n "$VOICE" ]] || fail "No Mandarin voice found; add one in System Settings > Accessibility > Spoken Content > System Voice"

mkdir -p "$AUDIO_DIR"
# Another voice makes different audio, so its recordings can't be compared with the cached ones.
if [[ ! -f "$AUDIO_DIR/voice" || "$(<"$AUDIO_DIR/voice")" != "$VOICE" ]]; then
    rm -f "$AUDIO_DIR"/*(N)
    print -rn -- "$VOICE" > "$AUDIO_DIR/voice"
fi

# NN.txt keeps the sentence NN.wav was spoken from; the eval refuses audio that no longer matches.
index=0
while spoken="$(plutil -extract "$index.spoken" raw -o - "$FIXTURE" 2>/dev/null)"; do
    name="$(printf '%02d' $((index + 1)))"
    wav="$AUDIO_DIR/$name.wav"
    text="$AUDIO_DIR/$name.txt"
    if [[ ! -f "$wav" || ! -f "$text" || "$(<"$text")" != "$spoken" ]]; then
        say -v "$VOICE" -o "$AUDIO_DIR/$name.aiff" "$spoken"
        # What the app records and uploads: 16 kHz mono 16-bit PCM WAV.
        afconvert -f WAVE -d LEI16@16000 -c 1 "$AUDIO_DIR/$name.aiff" "$wav"
        rm "$AUDIO_DIR/$name.aiff"
        print -rn -- "$spoken" > "$text"
        print -r -- "Spoke $name with $VOICE"
    fi
    (( index += 1 ))
done
(( index > 0 )) || fail "Could not read any sentence from $FIXTURE"

cd "$ROOT_DIR"
SAYKUKU_LIVE_QWEN_TEST=1 swift test --filter MixedLanguageEvalTests
