import CryptoKit
import Foundation
import Security

protocol LocalSecretStoring: AnyObject {
    func read(account: String) throws -> String?
    func write(_ value: String, account: String) throws
    func delete(account: String) throws
}

final class KeychainLocalSecretStore: LocalSecretStoring {
    private let service: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "com.linlu.leafreader") + ".api-credentials") {
        self.service = service
    }

    func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status, operation: "read")
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw keychainError(status: errSecDecode, operation: "decode")
        }
        return value
    }

    func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            try check(updateStatus, operation: "update")
        }
        var item = query
        attributes.forEach { item[$0.key] = $0.value }
        try check(SecItemAdd(item as CFDictionary, nil), operation: "add")
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status != errSecItemNotFound {
            try check(status, operation: "delete")
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == errSecSuccess else {
            throw keychainError(status: status, operation: operation)
        }
    }

    private func keychainError(status: OSStatus, operation: String) -> NSError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: "Keychain \(operation) failed: \(message)"]
        )
    }
}

enum LocalEncryptedStore {
    private static var secretStore: LocalSecretStoring = KeychainLocalSecretStore()
    private static var legacyDefaults: UserDefaults = .standard

    static func string(forKey key: String) -> String {
        do {
            if let value = try secretStore.read(account: key) {
                return normalized(value)
            }
        } catch {
            logFailure("read", error: error)
        }

        guard let legacyValue = legacyString(forKey: key) else { return "" }
        if save(legacyValue, forKey: key) {
            legacyDefaults.removeObject(forKey: key)
        }
        return legacyValue
    }

    @discardableResult
    static func save(_ value: String, forKey key: String) -> Bool {
        let trimmed = normalized(value)
        do {
            if trimmed.isEmpty {
                try secretStore.delete(account: key)
                return true
            }
            try secretStore.write(trimmed, account: key)
            guard normalized(try secretStore.read(account: key) ?? "") == trimmed else {
                throw NSError(
                    domain: "LeafReader.LocalSecretStore",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Keychain verification failed"]
                )
            }
            legacyDefaults.removeObject(forKey: key)
            return true
        } catch {
            logFailure(trimmed.isEmpty ? "delete" : "write", error: error)
            return false
        }
    }

    static func withStore<T>(
        _ store: LocalSecretStoring,
        legacyDefaults defaults: UserDefaults,
        perform work: () throws -> T
    ) rethrows -> T {
        let previousStore = secretStore
        let previousDefaults = legacyDefaults
        secretStore = store
        legacyDefaults = defaults
        defer {
            secretStore = previousStore
            legacyDefaults = previousDefaults
        }
        return try work()
    }

    private static func legacyString(forKey key: String) -> String? {
        guard let encoded = legacyDefaults.string(forKey: key),
              let data = Data(base64Encoded: encoded),
              let sealedBox = try? AES.GCM.SealedBox(combined: data),
              let decrypted = try? AES.GCM.open(sealedBox, using: legacyEncryptionKey),
              let value = String(data: decrypted, encoding: .utf8) else {
            return nil
        }
        let trimmed = normalized(value)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static var legacyEncryptionKey: SymmetricKey {
        let material = [
            "LeafReaderLocalEncryptedAPIKey",
            Bundle.main.bundleIdentifier ?? "com.linlu.leafreader",
            NSUserName(),
            NSHomeDirectory()
        ].joined(separator: "|")
        return SymmetricKey(data: Data(SHA256.hash(data: Data(material.utf8))))
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func logFailure(_ operation: String, error: Error) {
        NSLog("LeafReader secure credentials: %@ failed (%@)", operation, error.localizedDescription)
    }
}
