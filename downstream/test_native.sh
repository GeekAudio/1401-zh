#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
xcrun swiftc -O -framework SwiftUI -framework AppKit \
  mac/Sources/NativeUI.swift mac/Sources/NativeModel.swift mac/Sources/NativePageView.swift mac/Sources/NativePageNode.swift mac/Sources/NativeStyle.swift mac/Sources/NativeActionButton.swift mac/Sources/NativeTask.swift mac/Sources/NativeTaskState.swift mac/Sources/NativeTaskProgress.swift mac/Sources/ChineseDialogs.swift mac/Sources/ZH.swift mac/Sources/Downstream.swift \
  mac/Sources/ReleaseSignature.swift mac/Sources/AppReleaseSignature.swift mac/Sources/UpdateChannel.swift downstream/tests/ProgressTests.swift downstream/tests/main.swift -o "$TEMP_DIR/native-tests"
"$TEMP_DIR/native-tests" | tee dist/test-results.txt
xcrun swiftc -O mac/Sources/redaction.swift mac/tests/redaction/main.swift -o "$TEMP_DIR/redaction-tests"
"$TEMP_DIR/redaction-tests" | tee -a dist/test-results.txt
# Verify identical bundle bytes outside FileProvider folders that attach FinderInfo automatically.
TEST_APP="$TEMP_DIR/1401 中文版.app"
ditto --norsrc --noextattr 'dist/1401 中文版.app' "$TEST_APP"
xattr -cr "$TEST_APP"
codesign --verify --deep --strict "$TEST_APP"
if otool -L "$TEST_APP/Contents/MacOS/1401" | grep -q WebKit; then echo 'Unexpected WebKit dependency'; exit 1; fi
for PAGE_ID in drv efi tools usb crash; do
  "$TEST_APP/Contents/MacOS/1401" --ui-page "$PAGE_ID" --ui-snapshot "$PWD/dist/ui-$PAGE_ID.png"
  test -s "dist/ui-$PAGE_ID.png"
  "$TEST_APP/Contents/MacOS/1401" --ui-page "$PAGE_ID" --ui-progress --ui-snapshot "$PWD/dist/ui-progress-$PAGE_ID.png"
  test -s "dist/ui-progress-$PAGE_ID.png"
done
"$TEST_APP/Contents/MacOS/1401" --ui-page drv --ui-progress --ui-focus updr --ui-snapshot "$PWD/dist/ui-progress-updates.png"
test -s dist/ui-progress-updates.png
"$TEST_APP/Contents/MacOS/1401" --ui-page crash --ui-snapshot "$PWD/dist/ui-crash-dark.png" -theme dark
test -s dist/ui-crash-dark.png
"$TEST_APP/Contents/MacOS/1401" --ui-page crash --ui-progress --ui-snapshot "$PWD/dist/ui-progress-crash-dark.png" -theme dark
test -s dist/ui-progress-crash-dark.png
cp dist/ui-drv.png dist/ui-preview.png
echo 'Native UI rendered; bundle signature verified; no WebKit dependency' | tee -a dist/test-results.txt
