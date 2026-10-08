import AuthenticationServices
import LocalAuthentication
import Security
import Sodium  // https://github.com/jedisct1/swift-sodium (SPM)
import UIKit

/// iOS AutoFill Credential Provider.
///
/// Runs in a separate, memory-limited process (~120 MB), so it does NOT run
/// Flutter or Argon2. The main app keeps an encrypted snapshot of the vault
/// in the App Group container:
///   snapshot = 0x01 || nonce(24) || XChaCha20-Poly1305(json, AD "vaultsnap/v1/autofill-snapshot")
/// The 256-bit snapshot key lives in the shared Keychain with
/// `.biometryCurrentSet`: reading it triggers Face ID / Touch ID.
final class CredentialProviderViewController: ASCredentialProviderViewController {
  private struct Item: Decodable {
    let id: String
    let title: String
    let user: String
    let pass: String
    let host: String
  }

  private var items: [Item] = []
  private var filter: [ASCredentialServiceIdentifier] = []
  private let table = UITableView()

  private static var keychainGroup: String {
    Bundle.main.object(forInfoDictionaryKey: "VSKeychainGroup") as? String ?? ""
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    table.dataSource = self
    table.delegate = self
    table.frame = view.bounds
    table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(table)
  }

  // QuickType bar selection: the record id is known; fill without UI if
  // possible (the Keychain read still requires biometrics).
  override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
    extensionContext.cancelRequest(
      withError: NSError(
        domain: ASExtensionErrorDomain,
        code: ASExtensionError.userInteractionRequired.rawValue))
  }

  override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
    guard load() else { return cancel() }
    if let item = items.first(where: { $0.id == credentialIdentity.recordIdentifier }) {
      complete(item)
    } else {
      cancel()
    }
  }

  override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
    filter = serviceIdentifiers
    guard load() else { return cancel() }
    let hosts = serviceIdentifiers.compactMap { Self.host(of: $0) }
    items = items.filter { item in
      hosts.contains { h in h == item.host || h.hasSuffix("." + item.host) }
    }
    table.reloadData()
  }

  private static func host(of s: ASCredentialServiceIdentifier) -> String? {
    let raw = s.identifier.lowercased()
    let h = s.type == .URL ? URL(string: raw)?.host : raw
    guard var host = h else { return nil }
    if host.hasPrefix("www.") { host.removeFirst(4) }
    return host
  }

  /// Reads the key (biometric prompt) and decrypts the snapshot.
  private func load() -> Bool {
    let ctx = LAContext()
    ctx.localizedReason = "Unlock Khazna"
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: "autofill-snapshot-key",
      kSecAttrAccessGroup as String: Self.keychainGroup,
      kSecReturnData as String: true,
      kSecUseAuthenticationContext as String: ctx,
    ]
    var out: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
      var key = out as? Data, key.count == 32,
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.app.hisn.hisn"),
      let blob = try? Data(contentsOf: container.appendingPathComponent("autofill.snapshot")),
      blob.count > 41, blob[0] == 1
    else { return false }
    defer { key.resetBytes(in: 0..<key.count) }

    let sodium = Sodium()
    let nonce = Bytes(blob[1..<25])
    let ct = Bytes(blob[25...])
    guard
      var pt = sodium.aead.xchacha20poly1305ietf.decrypt(
        authenticatedCipherText: ct,
        secretKey: Bytes(key),
        nonce: nonce,
        additionalData: Bytes("vaultsnap/v1/autofill-snapshot".utf8))
    else { return false }
    defer { sodium.utils.zero(&pt) }
    items = (try? JSONDecoder().decode([Item].self, from: Data(pt))) ?? []
    return true
  }

  private func complete(_ item: Item) {
    extensionContext.completeRequest(
      withSelectedCredential: ASPasswordCredential(user: item.user, password: item.pass),
      completionHandler: nil)
    items = []
  }

  private func cancel() {
    items = []
    extensionContext.cancelRequest(
      withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.userCanceled.rawValue))
  }
}

extension CredentialProviderViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    cell.textLabel?.text = items[indexPath.row].title
    cell.detailTextLabel?.text = items[indexPath.row].user
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    complete(items[indexPath.row])
  }
}
