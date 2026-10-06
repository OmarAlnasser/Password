import AuthenticationServices
import Flutter
import LocalAuthentication
import Security
import UIKit

/// Shared between the app and the AutoFill extension (App Group + Keychain
/// access group must match the entitlements of both targets).
enum SharedConfig {
  static let appGroup = "group.app.vaultsnap.vaultsnap"
  /// "<TeamID>.app.vaultsnap.shared"; Info.plist key VSKeychainGroup is set
  /// to "$(AppIdentifierPrefix)app.vaultsnap.shared" so Xcode expands it.
  static var keychainGroup: String {
    Bundle.main.object(forInfoDictionaryKey: "VSKeychainGroup") as? String ?? ""
  }
  static let autofillKeyAccount = "autofill-snapshot-key"
  static let snapshotFile = "autofill.snapshot"
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var channel: FlutterMethodChannel?
  private var lastChangeCount: Int?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NotificationCenter.default.addObserver(
      self, selector: #selector(captureChanged),
      name: UIScreen.capturedDidChangeNotification, object: nil)
    AppDelegate.deleteStaleClipFiles()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Deletes pasted screenshots (tmp/clip-*.png) left behind when the app
  /// died before Dart could delete them. Recent ones may still be read by an
  /// OCR pass and are kept.
  nonisolated private static func deleteStaleClipFiles() {
    DispatchQueue.global(qos: .utility).async {
      let fm = FileManager.default
      let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      guard
        let files = try? fm.contentsOfDirectory(
          at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
      else { return }
      let cutoff = Date().addingTimeInterval(-10 * 60)
      for url in files {
        guard url.lastPathComponent.hasPrefix("clip-"), url.pathExtension == "png" else {
          continue
        }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        if let modified = values?.contentModificationDate, modified < cutoff {
          try? fm.removeItem(at: url)
        }
      }
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let ch = FlutterMethodChannel(
      name: "app.vaultsnap/platform",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    ch.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
    channel = ch
  }

  /// iOS cannot block screenshots/recording. When the screen is being
  /// recorded, mirrored or AirPlayed we tell Flutter to cover the content.
  @objc private func captureChanged() {
    channel?.invokeMethod("captureChanged", arguments: ["captured": UIScreen.main.isCaptured])
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "copySensitive":
      let text = args["text"] as? String ?? ""
      let ms = args["expiresInMs"] as? Int ?? 30_000
      // localOnly: never synced to other devices via Universal Clipboard.
      // expirationDate: iOS removes it even if we are suspended.
      UIPasteboard.general.setItems(
        [["public.utf8-plain-text": text]],
        options: [
          .localOnly: true,
          .expirationDate: Date().addingTimeInterval(Double(ms) / 1000.0),
        ])
      lastChangeCount = UIPasteboard.general.changeCount
      result(true)
    case "clearClipboardIfMatches":
      // Compare change counts instead of reading (reading shows the paste
      // banner and could expose other apps' data to us).
      if let c = lastChangeCount, UIPasteboard.general.changeCount == c {
        UIPasteboard.general.items = []
      }
      lastChangeCount = nil
      result(true)
    case "readClipboard":
      readClipboard(result)
    case "clearClipboard":
      UIPasteboard.general.items = []
      lastChangeCount = nil
      result(true)
    case "setSecureScreen":
      result(nil)
    case "deleteImage":
      result(false)  // image_picker does not expose the PHAsset id
    case "storeAutofillSnapshot":
      guard let key = (args["key"] as? FlutterStandardTypedData)?.data,
        let snapshot = (args["snapshot"] as? FlutterStandardTypedData)?.data,
        let identities = args["identities"] as? [[String: String]]
      else { return result(false) }
      result(storeAutofill(key: key, snapshot: snapshot, identities: identities))
    case "clearAutofill":
      clearAutofill()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// For the "Paste" button: a copied image (screenshot) is written as PNG to
  /// our tmp dir and returned as "imagePath" (Dart deletes it after OCR),
  /// otherwise the copied "text". Reading may show the system paste prompt;
  /// hasImages/hasStrings don't.
  private func readClipboard(_ result: @escaping FlutterResult) {
    let pasteboard = UIPasteboard.general
    if pasteboard.hasImages {
      guard let image = pasteboard.image else { return result([String: String]()) }
      // PNG encoding of a full-screen screenshot is slow; keep it off the
      // main thread, but answer Flutter on it.
      DispatchQueue.global(qos: .userInitiated).async {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
          .appendingPathComponent("clip-\(UUID().uuidString).png")
        var reply = [String: String]()
        if let png = AppDelegate.upright(image).pngData(),
          (try? png.write(to: url, options: [.atomic, .completeFileProtection])) != nil
        {
          reply["imagePath"] = url.path
        }
        DispatchQueue.main.async { result(reply) }
      }
      return
    }
    if pasteboard.hasStrings, let text = pasteboard.string, !text.isEmpty {
      return result(["text": text])
    }
    result([String: String]())
  }

  /// PNG has no orientation flag: bake it in so OCR sees upright text.
  /// Called off the main thread; UIGraphicsImageRenderer is thread-safe.
  nonisolated private static func upright(_ image: UIImage) -> UIImage {
    if image.imageOrientation == .up { return image }
    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale
    return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: image.size))
    }
  }

  /// Stores the snapshot key in the shared Keychain, readable only after
  /// Face ID / Touch ID with the *current* biometric set, this device only.
  private func storeAutofill(key: Data, snapshot: Data, identities: [[String: String]]) -> Bool {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: SharedConfig.appGroup)
    else { return false }
    var error: Unmanaged<CFError>?
    guard
      let access = SecAccessControlCreateWithFlags(
        nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
        .biometryCurrentSet, &error)
    else { return false }
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: SharedConfig.autofillKeyAccount,
      kSecAttrAccessGroup as String: SharedConfig.keychainGroup,
    ]
    SecItemDelete(base as CFDictionary)
    var add = base
    add[kSecValueData as String] = key
    add[kSecAttrAccessControl as String] = access
    guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return false }

    let url = container.appendingPathComponent(SharedConfig.snapshotFile)
    do {
      try snapshot.write(to: url, options: [.atomic, .completeFileProtection])
    } catch { return false }

    // QuickType bar suggestions: only service host + username + record id.
    let ids = identities.compactMap { m -> ASPasswordCredentialIdentity? in
      guard let host = m["host"], let user = m["user"], let id = m["id"] else { return nil }
      return ASPasswordCredentialIdentity(
        serviceIdentifier: ASCredentialServiceIdentifier(identifier: host, type: .domain),
        user: user, recordIdentifier: id)
    }
    ASCredentialIdentityStore.shared.replaceCredentialIdentities(with: ids) { _, _ in }
    return true
  }

  private func clearAutofill() {
    SecItemDelete(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: SharedConfig.autofillKeyAccount,
        kSecAttrAccessGroup as String: SharedConfig.keychainGroup,
      ] as CFDictionary)
    if let c = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: SharedConfig.appGroup)
    {
      try? FileManager.default.removeItem(at: c.appendingPathComponent(SharedConfig.snapshotFile))
    }
    ASCredentialIdentityStore.shared.removeAllCredentialIdentities { _, _ in }
  }
}
