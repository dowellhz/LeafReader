import Foundation

struct LocalRuntimeInstaller {
    let plan: LocalRuntimeDownloadPlan
    let install: (URL) throws -> Void

    func installDownloadedArchive(_ archiveURL: URL, asset: LocalRuntimeDownloadManifestAsset?) throws {
        try LocalRuntimeDownloadSupport.validateArchive(at: archiveURL)
        try LocalRuntimeDownloadSupport.validateArchiveManifest(archiveURL, asset: asset)
        try LocalRuntimeDownloadSupport.validateAvailableDiskSpace(for: plan, archiveURL: archiveURL, asset: asset)
        try install(archiveURL)
    }
}
