import Foundation

extension SpeechPlaybackCoordinator {
    struct PlaybackSegment {
        let outputURL: URL
        let speechText: String
        let text: String
        let matchText: String
        let index: Int
        let total: Int
        let pageIndex: Int?
    }

    struct SynthesisOptions {
        let speedMultiplier: Double?
        let piperLengthScale: Double?

        static let `default` = SynthesisOptions()
        static let normalSpeed = SynthesisOptions(speedMultiplier: 1.0, piperLengthScale: 1.0)

        init(speedMultiplier: Double? = nil, piperLengthScale: Double? = nil) {
            self.speedMultiplier = speedMultiplier
            self.piperLengthScale = piperLengthScale
        }

        var cacheSpeedID: String {
            if speedMultiplier == 1.0, piperLengthScale == 1.0 {
                return "normal"
            }
            return "settings-\(AISettingsStore.selectedSpeechSpeedID)"
        }
    }
}
