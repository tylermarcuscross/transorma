#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/toolchain.sh
xcrun swift test --scratch-path .build -Xswiftc -warnings-as-errors "$@"
