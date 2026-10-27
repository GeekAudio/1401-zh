#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
xcrun swiftc -O -framework SwiftUI -framework AppKit \
  mac/Sources/NativeUI.swift mac/Sources/ZH.swift mac/Sources/Downstream.swift \
  mac/Sources/ReleaseSignature.swift mac/Sources/AppReleaseSignature.swift mac/Sources/UpdateChannel.swift downstream/tests/main.swift -o "$TEMP_DIR/native-tests"
"$TEMP_DIR/native-tests" | tee dist/test-results.txt
xcrun swiftc -O mac/Sources/redaction.swift mac/tests/redaction/main.swift -o "$TEMP_DIR/redaction-tests"
"$TEMP_DIR/redaction-tests" | tee -a dist/test-results.txt
# Finder/FileProvider may attach FinderInfo to a freshly built .app in Documents.
xattr -cr 'dist/1401 中文版.app'
codesign --verify --deep --strict 'dist/1401 中文版.app'
if otool -L 'dist/1401 中文版.app/Contents/MacOS/1401' | grep -q WebKit; then echo 'Unexpected WebKit dependency'; exit 1; fi
'dist/1401 中文版.app/Contents/MacOS/1401' --ui-snapshot "$PWD/dist/ui-preview.png"
test -s dist/ui-preview.png
echo 'Native UI rendered; bundle signature verified; no WebKit dependency' | tee -a dist/test-results.txt
