#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/toolchain.sh
# Local development only. Release signing and App Groups remain in the Xcode project.
# Ad hoc signing permits launching/debugging the isolated UI without a developer team.
xcodebuild -project transorma.xcodeproj -scheme Transorma -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/Xcode \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    CODE_SIGN_ENTITLEMENTS= REGISTER_APP_GROUPS=NO \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES "${@:-build-for-testing}"
zsh scripts/index.sh
