import Foundation

enum SpeechRuntimeManifestTests {
    static func testSpeechModelManifestParsingAndChecksumValidation() throws {
        guard let manifestJSON = """
        {
          "generatedAt": "2026-05-23T06:08:12Z",
          "assets": [
            {
              "name": "piper-tts-macos-arm64.tar.gz",
              "size": 5,
              "sha256": "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
            }
          ]
        }
        """.data(using: .utf8) else {
            throw TestFailure(description: "could not encode manifest fixture")
        }
        let manifest = try SpeechRuntimeResourceManager.decodeModelManifest(manifestJSON)
        guard let asset = manifest.asset(named: "piper-tts-macos-arm64.tar.gz") else {
            throw TestFailure(description: "manifest lookup should return the matching asset")
        }
        try expectEqual(asset.sha256, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", "manifest lookup should return the matching asset digest")
        try expectEqual(asset.size, 5, "manifest lookup should return the matching asset size")

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-sha256-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("hello".utf8).write(to: fileURL)
        try LocalRuntimeDownloadSupport.validateArchiveManifest(fileURL, asset: asset)

        do {
            try LocalRuntimeDownloadSupport.validateArchiveChecksum(fileURL, expectedSHA256: String(repeating: "0", count: 64))
            throw TestFailure(description: "checksum mismatch should throw")
        } catch let error as NSError {
            try expectEqual(error.domain, LocalRuntimeDownloadSupport.downloadErrorDomain, "checksum mismatch should use the download error domain")
            try expectEqual(error.code, -7, "checksum mismatch should use the checksum error code")
        }

        let wrongSize = SpeechModelManifest.Asset(name: "piper-tts-macos-arm64.tar.gz", size: 6, sha256: asset.sha256)
        do {
            try LocalRuntimeDownloadSupport.validateArchiveManifest(fileURL, asset: wrongSize)
            throw TestFailure(description: "size mismatch should throw")
        } catch let error as NSError {
            try expectEqual(error.domain, LocalRuntimeDownloadSupport.downloadErrorDomain, "size mismatch should use the download error domain")
            try expectEqual(error.code, -8, "size mismatch should use the size error code")
        }
    }

    static func testSpeechModelManifestDecodeFallsBackToBundledManifest() throws {
        let bundled = SpeechModelManifest(
            generatedAt: "2026-05-25T00:00:00Z",
            assets: [
                SpeechModelManifest.Asset(
                    name: "piper-tts-macos-arm64.tar.gz",
                    size: 105541145,
                    sha256: "b752a7e93456c9b9eab397960976667153bee8c999ab497685fddb82562458b5"
                )
            ]
        )
        let fallbackResult = SpeechRuntimeResourceManager.modelManifestDecodeResult(
            data: Data("not json".utf8),
            bundledManifest: bundled
        )
        switch fallbackResult {
        case .success(let manifest):
            try expectEqual(
                manifest?.asset(named: "piper-tts-macos-arm64.tar.gz")?.size,
                105541145,
                "invalid remote manifest should fall back to the bundled manifest"
            )
        case .failure(let error):
            throw TestFailure(description: "invalid remote manifest should not fail when bundled manifest exists: \(error)")
        }

        let failureResult = SpeechRuntimeResourceManager.modelManifestDecodeResult(
            data: Data("not json".utf8),
            bundledManifest: nil
        )
        if case .success = failureResult {
            throw TestFailure(description: "invalid remote manifest should fail when no bundled manifest exists")
        }
    }

    static func testBundledSpeechModelManifestParses() throws {
        let manifestURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("mac-app/Resources/speech-models-manifest.json")
        let manifest = try SpeechRuntimeResourceManager.decodeModelManifest(Data(contentsOf: manifestURL))
        try expectEqual(
            manifest.asset(named: "kokoro-coreml-macos-arm64.tar.gz")?.size,
            694363430,
            "bundled manifest should include Kokoro model size"
        )
        try expectEqual(
            manifest.asset(named: "piper-tts-macos-arm64.tar.gz")?.sha256,
            "b752a7e93456c9b9eab397960976667153bee8c999ab497685fddb82562458b5",
            "bundled manifest should include Piper model checksum"
        )
        try expectEqual(
            manifest.asset(named: "supertonic-coreml-macos-arm64.tar.gz")?.size,
            187111483,
            "bundled manifest should include Supertonic CoreML archive size"
        )
        try expectEqual(
            manifest.asset(named: "supertonic-coreml-macos-arm64.tar.gz")?.sha256,
            "819d87657dac8f0febe630e55fe5b474171724cde98b86eb5fadad309e543397",
            "bundled manifest should include Supertonic CoreML archive checksum"
        )
    }
}
