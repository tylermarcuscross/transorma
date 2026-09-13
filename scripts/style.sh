#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/toolchain.sh
case "${1:-lint}" in
    format) transorma_style_args=(format --in-place) ;;
    lint) transorma_style_args=(lint --strict) ;;
    *) print -u2 'Usage: zsh scripts/style.sh [lint|format]'; exit 2 ;;
esac
xcrun swift-format "${transorma_style_args[@]}" --configuration .swift-format \
    --recursive Package.swift Sources Tests Tools transorma mailextension transormaUITests
