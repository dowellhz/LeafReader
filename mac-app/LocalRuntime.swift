import Foundation

enum LocalRuntimeFamily: String, Codable, Hashable {
    case speech
    case localLLM
}

struct LocalRuntimeInstallManifest: Codable, Equatable {
    let family: LocalRuntimeFamily
    let runtimeID: String
    let cacheDirectoryPaths: [String]

    init(family: LocalRuntimeFamily, runtimeID: String, cacheDirectoryPaths: [String]) {
        self.family = family
        self.runtimeID = runtimeID
        self.cacheDirectoryPaths = cacheDirectoryPaths
    }

    init(runtimeID: String, cacheDirectoryPaths: [String]) {
        self.init(family: .speech, runtimeID: runtimeID, cacheDirectoryPaths: cacheDirectoryPaths)
    }

    init(legacySpeechRuntimeID runtimeID: String, cacheDirectoryPaths: [String]) {
        self.init(family: .speech, runtimeID: runtimeID, cacheDirectoryPaths: cacheDirectoryPaths)
    }

    private enum CodingKeys: String, CodingKey {
        case family
        case runtimeID
        case cacheDirectoryPaths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        family = try container.decodeIfPresent(LocalRuntimeFamily.self, forKey: .family) ?? .speech
        runtimeID = try container.decode(String.self, forKey: .runtimeID)
        cacheDirectoryPaths = try container.decode([String].self, forKey: .cacheDirectoryPaths)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(family, forKey: .family)
        try container.encode(runtimeID, forKey: .runtimeID)
        try container.encode(cacheDirectoryPaths, forKey: .cacheDirectoryPaths)
    }
}

enum LocalRuntimeInstallState: Equatable {
    case complete
    case missingRuntime
    case missingModel
    case missingRuntimeAndModel

    static func state(hasRuntime: Bool, hasModel: Bool) -> LocalRuntimeInstallState {
        switch (hasRuntime, hasModel) {
        case (true, true):
            return .complete
        case (false, true):
            return .missingRuntime
        case (true, false):
            return .missingModel
        case (false, false):
            return .missingRuntimeAndModel
        }
    }
}

struct LocalRuntimeDescriptor {
    let family: LocalRuntimeFamily
    let id: String
    let title: String
    let summaryText: String
    let downloadSizeText: String
    let minimumSystemVersion: OperatingSystemVersion
    let minimumSystemVersionText: String
    let downloadURL: URL
    let manifestURL: URL?
    let installDirectory: URL
    let bundledInstallDirectory: URL?
    let installDirectories: [URL]
    let executableURL: URL
    let bundledExecutableURL: URL?
    let modelDirectory: URL
    let requiredPaths: [URL]
}

struct LocalRuntimeDownloadPlan {
    let descriptor: LocalRuntimeDescriptor
    let archiveURL: URL
    let manifestURL: URL?
    let expectedAssetName: String
}

struct LocalRuntimeDownloadKey: Hashable {
    let family: LocalRuntimeFamily
    let id: String

    init(family: LocalRuntimeFamily, id: String) {
        self.family = family
        self.id = id
    }

    init(descriptor: LocalRuntimeDescriptor) {
        self.init(family: descriptor.family, id: descriptor.id)
    }
}

struct LocalRuntimeRegistry {
    let downloadPlans: [LocalRuntimeDownloadPlan]

    var descriptors: [LocalRuntimeDescriptor] {
        downloadPlans.map(\.descriptor)
    }

    init(downloadPlans: [LocalRuntimeDownloadPlan]) {
        self.downloadPlans = downloadPlans
    }

    func descriptor(family: LocalRuntimeFamily, id: String) -> LocalRuntimeDescriptor? {
        descriptors.first { $0.family == family && $0.id == id }
    }

    func downloadPlan(family: LocalRuntimeFamily, id: String) -> LocalRuntimeDownloadPlan? {
        downloadPlans.first { $0.descriptor.family == family && $0.descriptor.id == id }
    }
}

struct LocalRuntimeStatusContext {
    let descriptor: LocalRuntimeDescriptor
    let installState: LocalRuntimeInstallState
    let isSupported: Bool
    let isDownloading: Bool
    let isPaused: Bool
    let downloadFailureMessage: String?
    let inferenceFailureText: String?
}

enum LocalRuntimeStatusPresenter {
    static func availabilityText(
        isSupported: Bool,
        downloaded: Bool,
        minimumSystemVersionText: String
    ) -> String? {
        guard !(isSupported && downloaded) else { return nil }
        if !isSupported {
            return AppText.localized(
                "需要 \(minimumSystemVersionText)",
                "Requires \(minimumSystemVersionText)"
            )
        }
        if downloaded {
            return AppText.localized("文件不完整", "Incomplete files")
        }
        return AppText.localized("未下载", "Not downloaded")
    }

    static func statusText(_ context: LocalRuntimeStatusContext) -> String {
        let descriptor = context.descriptor
        let size = descriptor.downloadSizeText
        let summary = descriptor.summaryText
        if context.isDownloading {
            if context.isPaused {
                return AppText.localized("已暂停 · \(size)", "Paused · \(size)")
            }
            return AppText.localized("下载中 · \(size)", "Downloading · \(size)")
        }
        if !context.isSupported {
            if context.installState == .complete {
                return AppText.localized(
                    "已下载 · 需要 \(descriptor.minimumSystemVersionText) 或更高",
                    "Downloaded · Requires \(descriptor.minimumSystemVersionText) or later"
                )
            }
            if let failure = context.downloadFailureMessage {
                return AppText.localized(
                    "未下载 · \(summary) · 需要 \(descriptor.minimumSystemVersionText) 或更高 · \(size) · 上次失败：\(failure)",
                    "Not downloaded · \(summary) · Requires \(descriptor.minimumSystemVersionText) or later · \(size) · Last failed: \(failure)"
                )
            }
            return AppText.localized(
                "未下载 · \(summary) · 需要 \(descriptor.minimumSystemVersionText) 或更高 · \(size)",
                "Not downloaded · \(summary) · Requires \(descriptor.minimumSystemVersionText) or later · \(size)"
            )
        }
        if context.installState == .complete {
            if let failure = context.inferenceFailureText {
                return AppText.localized(
                    "已安装 · \(size) · \(failure)",
                    "Installed · \(size) · \(failure)"
                )
            }
            return AppText.localized("已安装 · \(size)", "Installed · \(size)")
        }
        if let text = incompleteInstallStatusText(descriptor: descriptor, installState: context.installState) {
            return text
        }
        if let failure = context.downloadFailureMessage {
            return AppText.localized(
                "未下载 · \(summary) · \(size) · 上次失败：\(failure)",
                "Not downloaded · \(summary) · \(size) · Last failed: \(failure)"
            )
        }
        return AppText.localized("未下载 · \(summary) · \(size)", "Not downloaded · \(summary) · \(size)")
    }

    static func incompleteInstallStatusText(
        descriptor: LocalRuntimeDescriptor,
        installState: LocalRuntimeInstallState
    ) -> String? {
        switch installState {
        case .missingRuntime:
            return AppText.localized(
                "缺少运行时 · 模型已安装 · \(descriptor.downloadSizeText)",
                "Missing runtime · Model installed · \(descriptor.downloadSizeText)"
            )
        case .complete, .missingModel, .missingRuntimeAndModel:
            return nil
        }
    }
}
