# iOS AutoFill extension – Xcode setup

The source is ready, but the extension target must be added in Xcode (the
`.pbxproj` cannot be safely generated outside Xcode):

1. File ▸ New ▸ Target ▸ **AutoFill Credential Provider Extension**,
   name `AutoFillExtension`, bundle id `app.hisn.hisn.autofill`.
2. Replace the generated files with the ones in this folder
   (`CredentialProviderViewController.swift`, `Info.plist`,
   `AutoFillExtension.entitlements`).
3. File ▸ Add Package Dependencies ▸ `https://github.com/jedisct1/swift-sodium`
   (exact version pin), add `Sodium` to the extension target only.
4. Signing & Capabilities for **both** Runner and AutoFillExtension:
   App Groups `group.app.hisn.hisn`, Keychain Sharing
   `app.hisn.shared`, AutoFill Credential Provider.
5. Set Runner's `CODE_SIGN_ENTITLEMENTS` to `Runner/Runner.entitlements`.
