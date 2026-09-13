#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Some macOS 27 Command Line Tools builds omit this plugin search path in SwiftPM.
transorma_swiftc="$(xcrun --find swiftc)"
transorma_plugins="${transorma_swiftc:h:h}/lib/swift/host/plugins/testing"
if [[ -d "$transorma_plugins" ]]; then
    swift test --scratch-path .build -Xswiftc -plugin-path -Xswiftc "$transorma_plugins" "$@"
else
    swift test --scratch-path .build "$@"
fi
