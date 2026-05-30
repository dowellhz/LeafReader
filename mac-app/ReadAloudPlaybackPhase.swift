import Foundation

enum ReadAloudPlaybackPhase: Equatable {
    case idle
    case loading
    case playing
    case paused

    var isActive: Bool {
        self != .idle
    }

    var isLoading: Bool {
        self == .loading
    }

    var isPaused: Bool {
        self == .paused
    }
}

enum ReadAloudPlaybackEvent: Equatable {
    case startLoading
    case playbackStarted
    case pause
    case resume
    case stop
}
