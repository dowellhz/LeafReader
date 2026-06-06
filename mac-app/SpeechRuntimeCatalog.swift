import Foundation

enum SpeechRuntimeCatalog {
    typealias Runtime = SpeechRuntimeResourceManager.Runtime

    static var registry: LocalRuntimeRegistry {
        LocalRuntimeRegistry(downloadPlans: downloadPlans)
    }

    static var descriptors: [LocalRuntimeDescriptor] {
        registry.descriptors
    }

    static var downloadPlans: [LocalRuntimeDownloadPlan] {
        Runtime.displayOrder.map(downloadPlan(for:))
    }

    static func descriptor(for runtime: Runtime) -> LocalRuntimeDescriptor {
        LocalRuntimeDescriptor(
            family: .speech,
            id: runtime.id,
            title: runtime.title,
            summaryText: runtime.summaryText,
            downloadSizeText: runtime.downloadSizeText,
            minimumSystemVersion: runtime.minimumSystemVersion,
            minimumSystemVersionText: runtime.minimumSystemVersionText,
            downloadURL: runtime.downloadURL,
            manifestURL: runtime.manifestURL,
            installDirectory: runtime.installDirectory,
            bundledInstallDirectory: runtime.bundledInstallDirectory,
            installDirectories: runtime.installDirectories,
            executableURL: runtime.userExecutableURL,
            bundledExecutableURL: runtime.bundledExecutableURL,
            modelDirectory: runtime.modelDirectory(in: runtime.installDirectory),
            requiredPaths: runtime.requiredPaths
        )
    }

    static func downloadPlan(for runtime: Runtime) -> LocalRuntimeDownloadPlan {
        let descriptor = descriptor(for: runtime)
        return LocalRuntimeDownloadPlan(
            descriptor: descriptor,
            archiveURL: descriptor.downloadURL,
            manifestURL: descriptor.manifestURL,
            expectedAssetName: descriptor.downloadURL.lastPathComponent
        )
    }
}
