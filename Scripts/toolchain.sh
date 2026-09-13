#!/bin/zsh
# Run a command with a compatible Xcode. An explicit DEVELOPER_DIR wins.
set -euo pipefail
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    transorma_selected="$(xcode-select -p 2>/dev/null || true)"
    for transorma_candidate in "$transorma_selected" /Applications/Xcode-27.app/Contents/Developer /Applications/Xcode.app/Contents/Developer; do
        [[ -x "$transorma_candidate/usr/bin/xcodebuild" ]] || continue
        transorma_version="$(DEVELOPER_DIR="$transorma_candidate" xcodebuild -version 2>/dev/null)"
        transorma_major="${${transorma_version#Xcode }%%.*}"
        if [[ "$transorma_major" == <-> && "$transorma_major" -ge 27 ]]; then
            export DEVELOPER_DIR="$transorma_candidate"
            break
        fi
    done
fi
if [[ -z "${DEVELOPER_DIR:-}" || ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
    print -u2 'Install Xcode 27 or newer and set DEVELOPER_DIR to its Contents/Developer directory.'
    exit 1
fi
transorma_version="$(xcodebuild -version)"
transorma_major="${${transorma_version#Xcode }%%.*}"
if [[ "$transorma_major" != <-> || "$transorma_major" -lt 27 ]]; then
    print -u2 "Xcode 27 or newer is required. Selected: $transorma_version"
    exit 1
fi
if (( $# == 0 )); then
    print -r -- "$DEVELOPER_DIR"
else
    exec "$@"
fi
