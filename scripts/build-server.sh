#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/toolchain.sh
for transorma_server in /opt/homebrew/bin/xcode-build-server /usr/local/bin/xcode-build-server; do
    if [[ -x "$transorma_server" ]]; then
        exec "$transorma_server"
    fi
done
print -u2 'Install the VS Code build adapter: brew install xcode-build-server'
exit 1
