#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DIST_DIR=${1:-"$PWD/dist"}
mkdir -p "$DIST_DIR"
DIST_DIR=$(cd "$DIST_DIR" && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
xcrun swiftc -O mac/Sources/DriverSettings.swift mac/Sources/NativeSettingsSafety.swift mac/Sources/ZH.swift \
  downstream/tests/settings_safety/main.swift -o "$TEMP_DIR/settings-safety-tests"
"$TEMP_DIR/settings-safety-tests" mac/Resources/settings_catalog.json
xcrun swiftc -O -framework SwiftUI mac/Sources/DriverSettings.swift downstream/NativeSettingsControls.swift mac/Sources/ZH.swift \
  downstream/tests/settings_controls/main.swift -o "$TEMP_DIR/settings-controls-tests"
"$TEMP_DIR/settings-controls-tests" mac/Resources/settings_catalog.json
xcrun swiftc -O -import-objc-header mac/Sources/NativeProgressBridge.h -framework SwiftUI -framework AppKit \
  mac/Sources/NativeUI.swift mac/Sources/NativeNavigation.swift mac/Sources/NativeModel.swift mac/Sources/NativePageView.swift mac/Sources/NativePageNode.swift mac/Sources/NativeStyle.swift mac/Sources/NativeActionButton.swift mac/Sources/NativeTask.swift mac/Sources/NativeTaskState.swift mac/Sources/NativeTaskProgress.swift mac/Sources/ChineseDialogs.swift mac/Sources/ZH.swift mac/Sources/Downstream.swift \
  mac/Sources/AppUpdateRelease.swift mac/Sources/AppUpdateClient.swift mac/Sources/GitHubRetry.swift mac/Sources/AutomaticAppUpdates.swift mac/Sources/NativeProgressSession.swift mac/Sources/ReleaseSignature.swift mac/Sources/AppReleaseSignature.swift mac/Sources/UpdateChannel.swift downstream/tests/AutomaticUpdateTests.swift downstream/tests/UpdateClientTests.swift downstream/tests/ProgressTests.swift downstream/tests/main.swift -o "$TEMP_DIR/native-tests"
"$TEMP_DIR/native-tests" -AppleLanguages '(zh-Hans)' | tee "$DIST_DIR/test-results.txt"
xcrun swiftc -O mac/Sources/redaction.swift mac/tests/redaction/main.swift -o "$TEMP_DIR/redaction-tests"
"$TEMP_DIR/redaction-tests" | tee -a "$DIST_DIR/test-results.txt"
# Verify identical bundle bytes outside FileProvider folders that attach FinderInfo automatically.
TEST_APP="$TEMP_DIR/1401 中文版.app"
ditto --norsrc --noextattr "$DIST_DIR/1401 中文版.app" "$TEST_APP"
xattr -cr "$TEST_APP"
codesign --verify --deep --strict "$TEST_APP"
if otool -L "$TEST_APP/Contents/MacOS/1401" | grep -q WebKit; then echo 'Unexpected WebKit dependency'; exit 1; fi
SNAPSHOT=("$TEST_APP/Contents/MacOS/1401" -AppleLanguages '(zh-Hans)' --ui-expect-language zh-Hans)
for PAGE_ID in drv efi tools experimental usb crash; do
  "${SNAPSHOT[@]}" --ui-page "$PAGE_ID" --ui-snapshot "$DIST_DIR/ui-$PAGE_ID.png"
  test -s "$DIST_DIR/ui-$PAGE_ID.png"
  if [[ "$PAGE_ID" == experimental ]]; then
    "${SNAPSHOT[@]}" --ui-page "$PAGE_ID" --ui-progress --ui-focus expr --ui-snapshot "$DIST_DIR/ui-progress-$PAGE_ID.png"
  else
    "${SNAPSHOT[@]}" --ui-page "$PAGE_ID" --ui-progress --ui-snapshot "$DIST_DIR/ui-progress-$PAGE_ID.png"
  fi
  test -s "$DIST_DIR/ui-progress-$PAGE_ID.png"
done
for CATEGORY in display apps test-drivers; do
  PAGE_ID=tools
  if [[ "$CATEGORY" == test-drivers ]]; then PAGE_ID=experimental; fi
  "${SNAPSHOT[@]}" --ui-page "$PAGE_ID" --ui-category "$CATEGORY" --ui-snapshot "$DIST_DIR/ui-$PAGE_ID-$CATEGORY.png"
  test -s "$DIST_DIR/ui-$PAGE_ID-$CATEGORY.png"
done
"${SNAPSHOT[@]}" --ui-page drv --ui-progress --ui-focus updr --ui-snapshot "$DIST_DIR/ui-progress-updates.png"
test -s "$DIST_DIR/ui-progress-updates.png"
"${SNAPSHOT[@]}" --ui-page crash --ui-snapshot "$DIST_DIR/ui-crash-dark.png" -theme dark
test -s "$DIST_DIR/ui-crash-dark.png"
"${SNAPSHOT[@]}" --ui-page crash --ui-progress --ui-snapshot "$DIST_DIR/ui-progress-crash-dark.png" -theme dark
test -s "$DIST_DIR/ui-progress-crash-dark.png"
"$TEST_APP/Contents/MacOS/1401" -AppleLanguages '(en-US)' --ui-expect-language en \
  --ui-page tools --ui-category display --ui-snapshot "$DIST_DIR/ui-tools-en.png"
test -s "$DIST_DIR/ui-tools-en.png"
"$TEST_APP/Contents/MacOS/1401" -AppleLanguages '(zh-TW)' --ui-expect-language zh-Hant \
  --ui-page efi --ui-progress --ui-snapshot "$DIST_DIR/ui-efi-zh-Hant.png"
test -s "$DIST_DIR/ui-efi-zh-Hant.png"
cp "$DIST_DIR/ui-drv.png" "$DIST_DIR/ui-preview.png"
echo 'Native UI rendered; bundle signature verified; no WebKit dependency' | tee -a "$DIST_DIR/test-results.txt"
