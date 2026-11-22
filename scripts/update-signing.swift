import Foundation
import CryptoKit
import Security

// This tool never prints a private key. Keychain is the default key store.
// FOCUS_SIGNING_KEY_FILE is an optional, explicit path to a 32-byte Ed25519 seed.
let service = "dev.focuselle.update-signing"
let account = "ed25519"
let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                            kSecAttrService as String: service, kSecAttrAccount as String: account]
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
func loadKey(create: Bool) throws -> Curve25519.Signing.PrivateKey {
    if let path = ProcessInfo.processInfo.environment["FOCUS_SIGNING_KEY_FILE"] {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: url))
        }
        guard create else { fail("Signing key file not found") }
        let key = Curve25519.Signing.PrivateKey()
        // Do not overwrite an existing key; restrictive permissions from creation.
        let created = FileManager.default.createFile(atPath: path, contents: key.rawRepresentation,
                                                     attributes: [.posixPermissions: 0o600])
        guard created else { fail("Cannot create signing key file") }
        return key
    }
    var read = query
    read[kSecReturnData as String] = true
    read[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(read as CFDictionary, &result)
    if status == errSecSuccess, let data = result as? Data {
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }
    guard status == errSecItemNotFound, create else {
        fail("Cannot read update signing key from Keychain (status \(status)). Run the init command first.")
    }
    let key = Curve25519.Signing.PrivateKey()
    var entry = query
    entry[kSecValueData as String] = key.rawRepresentation
    entry[kSecAttrLabel as String] = "Focuselle update signing"
    entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let added = SecItemAdd(entry as CFDictionary, nil)
    guard added == errSecSuccess else { fail("Cannot save update signing key in Keychain (status \(added))") }
    return key
}
let args = CommandLine.arguments
let action = args.count > 1 ? args[1] : ""
do {
    switch action {
    case "init", "public-key":
        let key = try loadKey(create: action == "init")
        print(key.publicKey.rawRepresentation.base64EncodedString())
    case "sign":
        guard args.count == 3 else { fail("Usage: update-signing sign archive.zip") }
        let key = try loadKey(create: false)
        let data = try Data(contentsOf: URL(fileURLWithPath: args[2]), options: .mappedIfSafe)
        let signature = try key.signature(for: data)
        guard key.publicKey.isValidSignature(signature, for: data) else { fail("Signature self-check failed") }
        print(signature.base64EncodedString())
    case "verify":
        guard args.count == 5, let publicBytes = Data(base64Encoded: args[3]),
              let signature = Data(base64Encoded: args[4]) else {
            fail("Usage: update-signing verify archive.zip public-key signature")
        }
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)
        let data = try Data(contentsOf: URL(fileURLWithPath: args[2]), options: .mappedIfSafe)
        guard publicKey.isValidSignature(signature, for: data) else { fail("Invalid update signature") }
        print("Signature verified")
    default: fail("Usage: update-signing init | public-key | sign archive.zip | verify archive.zip public-key signature")
    }
} catch { fail(error.localizedDescription) }
