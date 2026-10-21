#!/bin/zsh
set -euo pipefail

# Kept for existing instructions; the suites share Scripts/eval-dictation.sh.
exec "${0:A:h}/eval-dictation.sh" mixed-language
