#!/bin/zsh
# Use the same Xcode selection as the editor. An explicit DEVELOPER_DIR wins.
set -euo pipefail
transorma_selection='DEVELOPER_DIR override'
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    DEVELOPER_DIR="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
    transorma_selection='xcode-select'
fi
export DEVELOPER_DIR
if [[ -z "${DEVELOPER_DIR:-}" || ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
    print -u2 "A full Xcode 27 or newer is required. $transorma_selection selected: ${DEVELOPER_DIR:-nothing}"
    print -u2 'Select it in Xcode > Settings > Locations > Command Line Tools, or run:'
    print -u2 '  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer'
    print -u2 'Remove an outdated DEVELOPER_DIR override if one is set.'
    exit 1
fi
transorma_version="$(/usr/bin/xcodebuild -version)"
transorma_first_line="${transorma_version%%$'\n'*}"
transorma_major="${${transorma_first_line#Xcode }%%.*}"
if [[ "$transorma_major" != <-> || "$transorma_major" -lt 27 ]]; then
    print -u2 "Xcode 27 or newer is required. Selected: $transorma_version"
    exit 1
fi
if [[ "${1:-}" == --doctor ]]; then
    print -r -- "Developer directory ($transorma_selection): $DEVELOPER_DIR"
    print -r -- "$transorma_version"
    /usr/bin/xcrun swift --version
    print -r -- "Swift compiler: $(/usr/bin/xcrun --find swiftc)"
    print -r -- "macOS SDK: $(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
elif (( $# == 0 )); then
    print -r -- "$DEVELOPER_DIR"
else
    exec "$@"
fi
