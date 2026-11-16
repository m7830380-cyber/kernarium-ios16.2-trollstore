# iOS 16.2 / TrollStore build (experimental)

This fork adds a manually dispatched GitHub Actions workflow that downloads the public upstream Andarium 1.0 b9 IPA, patches its deployment metadata and selected imports for iOS 16.2, and outputs an ad-hoc-signed IPA intended for installation with TrollStore.

## Build

1. Open **Actions → Build iOS 16.2 TrollStore IPA → Run workflow**.
2. The `release` input defaults to off. The workflow always uploads an Actions artifact; enabling the input also creates a versioned GitHub release.
3. Download `Andarium-1.0-9-ios16.2-trollstore.ipa` and `report.txt` from the run/artifact (or release).
4. Install the IPA with TrollStore. Keep the original IPA available to roll back.

The workflow uses a current macOS runner/Xcode SDK to process the upstream arm64 Mach-O binaries. `vtool` changes each binary's minimum OS version to 16.2; `Info.plist` minimums are also lowered. Imports known to be newer than 16.2 are made weak where possible, and two newer audio notification imports are rebound to the older interruption notification. The package is ad-hoc-signed; it is not an App Store or conventional sideloading build.

## Limitations

Lowering a deployment target does **not** back-deploy newer SwiftUI or system frameworks. The patch only weakens a small known set of symbols, and the compatibility report cannot prove runtime compatibility. Some APIs, framework behavior, entitlements, JIT behavior, or device-specific requirements may still prevent launch or cause features to fail. This has not been validated on an iOS 16.2 device. Treat it as experimental, do not overwrite the original app, and report the full `report.txt` plus a device crash log when testing.

The source IPA is fetched from the upstream `imxieyi/Kernarium` GitHub release `1.0b9-beta`; the workflow does not commit or redistribute that source IPA in the repository.
