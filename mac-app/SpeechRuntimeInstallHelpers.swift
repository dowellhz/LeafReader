import Foundation

extension SpeechRuntimeResourceManager.InstallManifest {
    var cacheDirectories: [URL] {
        cacheDirectoryPaths.compactMap { path in
            let url = URL(fileURLWithPath: path, isDirectory: true)
            return (url.isInsideFluidAudioModelCache || url.isInsidePiperVoiceCache) ? url : nil
        }
    }
}

extension URL {
    var isInsideFluidAudioModelCache: Bool {
        isDescendant(of: SpeechRuntimeResourceManager.Runtime.fluidAudioModelCacheRoot)
    }

    var isInsidePiperVoiceCache: Bool {
        isDescendant(of: SpeechRuntimeResourceManager.Runtime.piperVoiceCacheRoot)
    }

    private func isDescendant(of root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        return standardizedFileURL.path.hasPrefix(rootPath + "/")
    }
}
