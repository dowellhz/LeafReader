import Foundation

struct UserDataBackupConfiguration {
    let applicationSupportDirectory: URL
    let preferencesDomainName: String
    let applicationBundleIdentifier: String
    let defaults: UserDefaults

    static func production(defaults: UserDefaults = .standard) -> UserDataBackupConfiguration? {
        guard let supportRoot = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let identifier = Bundle.main.bundleIdentifier ?? "com.linlu.LeafReader"
        return UserDataBackupConfiguration(
            applicationSupportDirectory: supportRoot.appendingPathComponent("LeafReader", isDirectory: true),
            preferencesDomainName: identifier,
            applicationBundleIdentifier: identifier,
            defaults: defaults
        )
    }
}

struct UserDataBackupManifest: Codable, Equatable {
    struct Entry: Codable, Equatable {
        enum Kind: String, Codable {
            case database
            case preferences
            case readingNoteAsset
        }

        let relativePath: String
        let kind: Kind
        let byteCount: Int64
        let sha256: String
    }

    let schemaVersion: Int
    let createdAt: Date
    let applicationBundleIdentifier: String
    let preferencesDomainName: String
    let includesReadingNoteAssetsDirectory: Bool
    let entries: [Entry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case createdAt = "created_at"
        case applicationBundleIdentifier = "application_bundle_identifier"
        case preferencesDomainName = "preferences_domain_name"
        case includesReadingNoteAssetsDirectory = "includes_reading_note_assets_directory"
        case entries
    }
}

struct UserDataRestoreResult: Equatable {
    let restoredEntryCount: Int
    let requiresRelaunch: Bool
}

enum UserDataBackupPreferencePolicy {
    private static let sensitivePrefixes = ["apiKey.", "encryptedApiKey."]

    static func isSensitiveKey(_ key: String) -> Bool {
        sensitivePrefixes.contains { key.hasPrefix($0) }
    }

    static func sanitized(_ domain: [String: Any]) -> [String: Any] {
        domain.filter { !isSensitiveKey($0.key) }
    }

    static func restoring(_ restored: [String: Any], preservingSensitiveValuesFrom current: [String: Any]) -> [String: Any] {
        var result = sanitized(restored)
        for (key, value) in current where isSensitiveKey(key) {
            result[key] = value
        }
        return result
    }
}

enum UserDataBackupError: LocalizedError {
    case destinationExists(String)
    case invalidBackup(String)
    case unsupportedSchema(Int)
    case incompatibleApplication(String)
    case fileOperation(String)
    case sqliteSnapshot(String)
    case sqliteIntegrity(String)
    case preferences(String)
    case rollbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .destinationExists(let path):
            return AppText.localized("备份位置已存在：\(path)", "A backup already exists at \(path).")
        case .invalidBackup(let reason):
            return AppText.localized("备份无效：\(reason)", "The backup is invalid: \(reason)")
        case .unsupportedSchema(let version):
            return AppText.localized("不支持备份格式版本 \(version)。", "Backup schema version \(version) is not supported.")
        case .incompatibleApplication(let identifier):
            return AppText.localized("备份属于其他应用：\(identifier)", "The backup belongs to another application: \(identifier)")
        case .fileOperation(let reason):
            return AppText.localized("备份文件操作失败：\(reason)", "Backup file operation failed: \(reason)")
        case .sqliteSnapshot(let name):
            return AppText.localized("无法备份数据库：\(name)", "Could not snapshot database: \(name)")
        case .sqliteIntegrity(let name):
            return AppText.localized("数据库完整性检查失败：\(name)", "SQLite integrity validation failed: \(name)")
        case .preferences(let reason):
            return AppText.localized("偏好设置处理失败：\(reason)", "Preferences processing failed: \(reason)")
        case .rollbackFailed(let reason):
            return AppText.localized("恢复失败且回滚不完整：\(reason)", "Restore failed and rollback was incomplete: \(reason)")
        }
    }
}

struct UserDataRestoreRequest: Codable {
    let backupPath: String
}

struct UserDataRestoreJournal: Codable {
    enum Phase: String, Codable {
        case applying
        case rollingBack
        case committed
    }

    struct Unit: Codable {
        enum Phase: String, Codable {
            case pending
            case movingOriginal
            case originalMoved
            case installingStaged
            case installed
        }

        let name: String
        let hadOriginal: Bool
        var phase: Phase
    }

    var phase: Phase
    var units: [Unit]
    var preferencesApplyStarted: Bool
    var preferencesApplied: Bool
}
