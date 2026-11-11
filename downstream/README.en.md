# 1401

[简体中文](README.md) · English

1401 is GeekAudio’s community-maintained macOS interface for the NullMoth NVIDIA driver. The app uses SwiftUI and AppKit. Driver installation, EFI checks, USB mapping, and hardware detection follow the upstream implementation.

[Download the latest release](https://github.com/GeekAudio/1401-zh/releases/latest) · [Report an issue](https://github.com/GeekAudio/1401-zh/issues) · [Upstream project](https://github.com/nullmoth/1401)

## Get started

The app follows your macOS language preferences and supports English, Simplified Chinese, and Traditional Chinese. If macOS does not match a supported language, the app uses English. You can set a language for 1401 in **System Settings → General → Language & Region → Applications**. Reopen the app for the change to take effect.

Download the latest `1401-Mac-*.zip`, extract it, and move **1401 中文版.app** to **Applications**. The NVIDIA driver requires an Intel-based (`x86_64`) system, macOS 15.5 or later within macOS 15 or macOS 26, and a supported NVIDIA GPU. Keep the OpenCore drive used to start your Mac connected. Download and preview the driver, review the listed changes, then install and restart. Installation backs up the OpenCore configuration. Driver packages come from the upstream address and follow the upstream verification process.

## Interface

The interface preserves the five upstream pages and adds a **Lab** tab for test drivers and experimental switches. The **Tools** page is grouped into **System & Startup**, **Display & Performance**, and **Apps & Permissions**. GPU measurement is under **Reports**. VMD and RAID guidance is under **Issues**. Both the upper-left app name and the centered window title display **1401**.

The window stays 820 pt wide and adjusts its height to the current page. Longer pages scroll inside the window. Light and dark appearances are supported.

## App updates and verification

The app checks this repository for updates about five seconds after launch and every hour while it is running. It downloads the release ZIP, checks its SHA-256, Ed25519 signature, bundle identifier, and version, then backs up and replaces the app and reopens it. The `.bsig` signature binds the product name, version, and SHA-256. The legacy `.sig` is also published for older app versions.

App replacement waits for active driver installation, log collection, EFI operations, GPU measurement, USB monitoring, and authorization tasks to finish. Manual and automatic checks share the same request and download locks.

When GitHub requests fail, are rate limited, or return a server error, update checks, checksum and signature downloads, and file downloads may retry through the public `gh-proxy.com` service. Only public GitHub URLs without credentials or query parameters are forwarded. The app still verifies downloaded files locally with its embedded public keys. The proxy may process request URLs and access records. If the GitHub API is unavailable, the app can read the checksum manifest from the fixed public release page and retries later if that also fails.

Use the driver controls to install or update the NVIDIA driver.

## Tools and diagnostics

**Display & Performance** includes driver settings, Game Mode, GPU boost, hybrid-graphics controls, and Ryzen power settings. Driver settings show the proposed changes before writing and verify the result afterward. Compatible Intel Xe systems on macOS 15.8 or 26.7 and later can find WhateverXe under **Lab → Test Drivers**.

**Apps & Permissions** can request microphone and camera permissions for a selected app. Optional ARM app support uses the NullMoth translator and stores translated copies in **Applications → NullMoth ARM**. Homebrew can be configured for ARM under `/opt/homebrew` and Intel under `/usr/local`. If the boot drive requested ARM app support, 1401 offers it the first time the app opens.

Mac Pro (2019) systems started with Apple firmware can install the driver through the upstream process with SIP disabled. Systems installed with OpenCore Legacy Patcher use the model configured by OCLP. The **System** page displays a connection note for an itlwm network adapter when HeliPort is missing.

EFI mounting and USB monitoring report text status. Log collection and upload, driver installation, app updates, WhateverXe setup, and GPU measurement show progress based on reported stages or completed work. Driver-update progress combines download and installation. A standalone driver download reports downloaded bytes. Progress stops on completion, failure, or cancellation.

## Upstream sync and releases

GitHub Actions checks the `nullmoth/1401` main branch every ten minutes. You can also run **Sync upstream and publish macOS Chinese edition** manually from the Actions page. When the upstream changes, the workflow synchronizes its source, reapplies this repository’s interface and app-update overlay, builds on macOS, runs tests, and publishes a release. The workflow stops if an upstream change breaks a patch anchor, translation coverage, tests, or the build.

Each release contains the app ZIP and DMG, SHA-256 checksums, a bound `.bsig` signature, and a legacy `.sig` signature. The app version combines the upstream driver version and a build number. The app-update signing key is separate from the upstream test-driver key. Driver package downloads, updates, signatures, diagnostic uploads, and test channels continue to use the upstream services.

Release signing requires the repository secret `RELEASE_SIGNING_KEY`, containing the Base64-encoded 32-byte Ed25519 private key. Its public key is stored in `downstream/release-public-key.txt` and compiled into the app. The private key must not be committed. Builds use ad hoc signing and are not notarized by Apple.

## Local build

```sh
git remote add upstream https://github.com/nullmoth/1401.git
git fetch upstream main
python3 downstream/apply.py --source-ref upstream/main --build 1
bash mac/build.sh ../dist
python3 downstream/check.py
python3 -m unittest discover -s tests -t . -p 'test_*.py'
```

`downstream/apply.py` rebuilds this overlay from a selected upstream commit and can be run repeatedly. `downstream/check.py` compares upstream operations and installer code, checks translations and UI page parity, and removes the documented overlays before comparison. A change to upstream page content or patch anchors requires review before release. The current upstream commit, driver version, app version, and build number are recorded in `downstream/state.json`.

This is a noncommercial community fork, maintained separately from the official upstream app. Copyright and licenses for the original author and third parties are preserved in [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). The app icon was created for this fork.
