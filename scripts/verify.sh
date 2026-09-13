#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/toolchain.sh
zsh scripts/style.sh lint
zsh scripts/test-core.sh
zsh scripts/build.sh
git diff --check
