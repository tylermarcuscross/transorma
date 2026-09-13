#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Read actual compiler invocations, including older full builds when the latest
# build is incremental. -o preserves the portable buildServer.json configuration.
transorma_server="$(command -v xcode-build-server || true)"
if [[ -z "$transorma_server" ]]; then
    for transorma_candidate in /opt/homebrew/bin/xcode-build-server /usr/local/bin/xcode-build-server; do
        [[ -x "$transorma_candidate" ]] && transorma_server="$transorma_candidate" && break
    done
fi
if [[ -z "$transorma_server" ]]; then
    print 'VS Code indexing skipped. Install its adapter with: brew install xcode-build-server'
    exit 0
fi
transorma_logs=(.build/Xcode/Logs/Build/*.xcactivitylog(NOm))
mkdir -p .build
: > .build/index.log
for transorma_log in "${transorma_logs[@]}"; do
    if ! "$transorma_server" parse -a -l "$transorma_log" -o .compile >> .build/index.log 2>&1; then
        cat .build/index.log >&2
        exit 1
    fi
done
print 'Updated VS Code build settings.'
