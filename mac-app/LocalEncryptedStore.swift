import Cocoa
import CryptoKit
import Foundation

enum LocalEncryptedStore {
    static func string(forKey key: String) -> String {
        guard
            let encoded = UserDefaults.standard.string(forKey: key),
            let data = Data(base64Encoded: encoded),
            let sealedBox = try? AES.GCM.SealedBox(combined: data),
            let decrypted = try? AES.GCM.open(sealedBox, using: encryptionKey),
            let value = String(data: decrypted, encoding: .utf8)
        else {
            return ""
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func save(_ value: String, forKey key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }

        if let sealedBox = try? AES.GCM.seal(Data(trimmed.utf8), using: encryptionKey),
           let combined = sealedBox.combined {
            UserDefaults.standard.set(combined.base64EncodedString(), forKey: key)
        }
    }

    private static var encryptionKey: SymmetricKey {
        let material = [
            "LeafReaderLocalEncryptedAPIKey",
            Bundle.main.bundleIdentifier ?? "com.linlu.leafreader",
            NSUserName(),
            NSHomeDirectory()
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: Data(digest))
    }
}
