import AVFoundation

extension SpeechPlaybackCoordinator {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if player === interruptionPlayer {
            finishInterruptionPlayback()
            return
        }
        guard !isStoppingPlayback else { return }
        finishCurrentPlaybackIfMatching(player)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        NSLog("LeafReader SpeechPlayback: AVAudioPlayer decode error: %@", String(describing: error))
        if player === interruptionPlayer {
            finishInterruptionPlayback()
            return
        }
        guard !isStoppingPlayback else { return }
        finishCurrentPlaybackIfMatching(player)
    }
}
