#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build --product TransormaCore --scratch-path .build
transorma_bin="$(swift build --show-bin-path --scratch-path .build)"
mkdir -p .build/Preview
xcrun swiftc -swift-version 6 -DDEBUG -parse-as-library -target arm64-apple-macos27.0 \
    -I "$transorma_bin" -L "$transorma_bin" -lTransormaCore \
    -Xcc -fmodule-map-file=Sources/CMailSystem/module.modulemap \
    -Xcc -iwithsysroot -Xcc /usr/include/libxml2 \
    -module-cache-path .build/PreviewModuleCache \
    transorma/ContentView.swift transorma/ProtectionModel.swift Tools/Preview/main.swift \
    -o .build/Preview/render
.build/Preview/render .build/Preview/Transorma.png --ui-testing
