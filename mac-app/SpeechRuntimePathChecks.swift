import Foundation

enum SpeechRuntimePathChecks {
    typealias Runtime = SpeechRuntimeResourceManager.Runtime

    static func requiredPathsExist(_ paths: [URL]) -> Bool {
        paths.allSatisfy { path in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory)
            if path.hasDirectoryPath {
                return exists && isDirectory.boolValue
            }
            return FileManager.default.isExecutableFile(atPath: path.path)
        }
    }

    static func kittenRuntimePathsExist(in directory: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: Runtime.kitten.executableURL(in: directory).path)
    }

    static func piperRuntimePathsExist(in directory: URL) -> Bool {
        let phonemizeLibraryDirectory = directory
            .appendingPathComponent("piper-phonemize/lib", isDirectory: true)
        let eSpeakDataDirectory = directory
            .appendingPathComponent("piper-phonemize/share/espeak-ng-data", isDirectory: true)
        return FileManager.default.isExecutableFile(atPath: Runtime.piper.executableURL(in: directory).path)
            && directoryExists(phonemizeLibraryDirectory)
            && directoryExists(eSpeakDataDirectory)
    }

    static func supertonicRuntimePathsExist(in directory: URL) -> Bool {
        let scriptURL = Runtime.supertonic.executableURL(in: directory)
        let packageURL = directory.appendingPathComponent("supertonic_mlx", isDirectory: true)
        return FileManager.default.fileExists(atPath: scriptURL.path)
            && directoryExists(packageURL)
    }

    static func piperVoicePathsExist(voiceID: String = SpeechVoiceCatalog.defaultPiperVoiceID) -> Bool {
        piperVoicePathsExist(in: Runtime.piper.modelDirectory(in: Runtime.piper.installDirectory), voiceID: voiceID)
    }

    static func piperAnyVoicePathsExist() -> Bool {
        piperAnyVoicePathsExist(in: Runtime.piper.modelDirectory(in: Runtime.piper.installDirectory))
    }

    static func piperVoicePathsExist(in modelDirectory: URL, voiceID: String = SpeechVoiceCatalog.defaultPiperVoiceID) -> Bool {
        let model = modelDirectory.appendingPathComponent("\(voiceID).onnx")
        let config = modelDirectory.appendingPathComponent("\(voiceID).onnx.json")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: modelDirectory.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.fileExists(atPath: model.path)
            && FileManager.default.fileExists(atPath: config.path)
    }

    static func piperAnyVoicePathsExist(in modelDirectory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: modelDirectory,
                includingPropertiesForKeys: nil
              ) else {
            return false
        }
        let modelIDs = Set(contents.filter { $0.pathExtension == "onnx" }.map { $0.deletingPathExtension().lastPathComponent })
        let configIDs = Set(contents.filter { $0.lastPathComponent.hasSuffix(".onnx.json") }.map {
            $0.lastPathComponent.replacingOccurrences(of: ".onnx.json", with: "")
        })
        return !modelIDs.intersection(configIDs).isEmpty
    }

    static func kittenModelPathsExist(in directory: URL) -> Bool {
        let modelDirectory = Runtime.kitten.modelDirectory(in: directory)
        return directoryExists(modelDirectory)
            && relativeFilesExist(
                [
                    "kitten_tts_mini_v0_8.onnx",
                    "voices.npz",
                    "config.json"
                ],
                in: modelDirectory
            )
    }

    static func kokoroModelCacheDirectories() -> [URL] {
        let cacheRoot = Runtime.fluidAudioModelCacheRoot
        return [
            cacheRoot.appendingPathComponent("kokoro", isDirectory: true),
            cacheRoot.appendingPathComponent("kokoro-82m-coreml", isDirectory: true)
        ]
    }

    static func piperVoiceCacheDirectories() -> [URL] {
        [Runtime.piperVoiceCacheRoot]
    }

    static func kokoroAneModelCacheExists() -> Bool {
        kokoroAneModelCacheExists(in: Runtime.fluidAudioModelCacheRoot)
    }

    static func kokoroAneModelCacheExists(in cacheRoot: URL) -> Bool {
        kokoroAneEnglishModelCacheExists(in: cacheRoot)
            || kokoroAneMandarinModelCacheExists(in: cacheRoot)
    }

    static func kokoroAneEnglishModelCacheExists(in cacheRoot: URL) -> Bool {
        let aneDirectory = cacheRoot
            .appendingPathComponent("kokoro-82m-coreml", isDirectory: true)
            .appendingPathComponent("ANE", isDirectory: true)
        let requiredAneFiles = [
            "KokoroAlbert.mlmodelc",
            "KokoroPostAlbert.mlmodelc",
            "KokoroAlignment.mlmodelc",
            "KokoroProsody.mlmodelc",
            "KokoroNoise.mlmodelc",
            "KokoroVocoder.mlmodelc",
            "KokoroTail.mlmodelc",
            "vocab.json"
        ]
        guard relativeFilesExist(requiredAneFiles, in: aneDirectory) else {
            return false
        }

        let g2pDirectory = cacheRoot.appendingPathComponent("kokoro", isDirectory: true)
        let requiredG2PFiles = [
            "G2PEncoder.mlmodelc",
            "G2PDecoder.mlmodelc",
            "g2p_vocab.json"
        ]
        return relativeFilesExist(requiredG2PFiles, in: g2pDirectory)
    }

    static func kokoroAneMandarinModelCacheExists(in cacheRoot: URL) -> Bool {
        let aneDirectory = cacheRoot
            .appendingPathComponent("kokoro-82m-coreml", isDirectory: true)
            .appendingPathComponent("ANE-zh", isDirectory: true)
        let requiredAneFiles = [
            "KokoroAlbert.mlmodelc",
            "KokoroPostAlbert.mlmodelc",
            "KokoroAlignment.mlmodelc",
            "KokoroProsody.mlmodelc",
            "KokoroNoise.mlmodelc",
            "KokoroVocoder.mlmodelc",
            "KokoroTail.mlmodelc",
            "vocab.json",
            "assets/pinyin_phrases.bin",
            "assets/pinyin_single.bin"
        ]
        return relativeFilesExist(requiredAneFiles, in: aneDirectory)
    }

    static func removeItemIfExists(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    static func relativeFilesExist(_ relativePaths: [String], in directory: URL) -> Bool {
        relativePaths.allSatisfy { relativePath in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(relativePath).path)
        }
    }
}
