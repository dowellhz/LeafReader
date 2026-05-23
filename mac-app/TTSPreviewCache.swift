import CryptoKit
import Foundation

enum TTSPreviewCache {
    static func audioURL(text: String, runtimeID: String, voiceID: String, speedID: String) -> URL {
        let digestInput = "preview-v4|\(runtimeID)|\(voiceID)|\(speedID)|\(text)"
        let digest = SHA256.hash(data: Data(digestInput.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "com.linlu.leafreader"
        return root
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("TTSPreviews", isDirectory: true)
            .appendingPathComponent("\(digest).wav")
    }
}
