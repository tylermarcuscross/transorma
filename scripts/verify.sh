#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
transorma_version="$(xcodebuild -version | head -1)"
transorma_major="${transorma_version#Xcode }"
transorma_major="${transorma_major%%.*}"
if [[ "$transorma_major" -lt 27 ]]; then
    print -u2 "Select Xcode 27 or newer before validating the app. Current: $transorma_version"
    exit 1
fi
zsh scripts/test-core.sh
xcodebuild -project transorma.xcodeproj -scheme Transorma -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath .build/Xcode \
    CODE_SIGNING_ALLOWED=NO build
git diff --check
