import Foundation
import Network

extension Notification.Name {
    static let leafReaderNetworkConnectivityChanged = Notification.Name("leafReaderNetworkConnectivityChanged")
}

final class NetworkConnectivityMonitor {
    static let shared = NetworkConnectivityMonitor()

    private enum State {
        case online
        case offline

        var isOnline: Bool {
            switch self {
            case .online:
                return true
            case .offline:
                return false
            }
        }
    }

    private enum Constants {
        static let networkErrorCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorTimedOut
        ]
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.linlu.leafreader.network-connectivity")
    private let lock = NSLock()
    private var state: State = .online

    var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.isOnline
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.setState(path.status == .satisfied ? .online : .offline)
        }
        monitor.start(queue: queue)
    }

    static func isNetworkConnectivityError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return Constants.networkErrorCodes.contains(nsError.code)
    }

    private func setState(_ newState: State) {
        lock.lock()
        let didChange = state.isOnline != newState.isOnline
        state = newState
        lock.unlock()
        guard didChange else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .leafReaderNetworkConnectivityChanged, object: self)
        }
    }

    deinit {
        monitor.cancel()
    }
}
