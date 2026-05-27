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
        static let probeTimeout: TimeInterval = 3
        static let retryDelay: TimeInterval = 5
        static let probeURL = URL(string: "https://www.apple.com/library/test/success.html")!
        static let reachableStatusCodes = 200..<400
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
    private var isProbeRunning = false
    private var retryProbeWorkItem: DispatchWorkItem?
    private lazy var probeSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Constants.probeTimeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.isOnline
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if path.status == .satisfied {
                self.probeInternet()
            } else {
                self.setState(.offline)
            }
        }
        monitor.start(queue: queue)
        probeInternet()
    }

    func markRequestSucceeded() {
        setState(.online)
    }

    func markNetworkFailure() {
        setState(.offline)
        scheduleRetryProbe()
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
        if newState.isOnline {
            cancelRetryProbe()
        }
        guard didChange else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .leafReaderNetworkConnectivityChanged, object: self)
        }
    }

    private func probeInternet() {
        lock.lock()
        guard !isProbeRunning else {
            lock.unlock()
            return
        }
        isProbeRunning = true
        lock.unlock()

        var request = URLRequest(url: Constants.probeURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = Constants.probeTimeout
        probeSession.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let isReachable = error == nil
                && statusCode.map { Constants.reachableStatusCodes.contains($0) } == true
            self.lock.lock()
            self.isProbeRunning = false
            self.lock.unlock()
            isReachable ? self.setState(.online) : self.markNetworkFailure()
        }.resume()
    }

    private func scheduleRetryProbe() {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isProbeRunning else { return }
            if self.retryProbeWorkItem?.isCancelled == false {
                return
            }
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.retryProbeWorkItem = nil
                self.probeInternet()
            }
            self.retryProbeWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + Constants.retryDelay, execute: workItem)
        }
    }

    private func cancelRetryProbe() {
        queue.async { [weak self] in
            self?.retryProbeWorkItem?.cancel()
            self?.retryProbeWorkItem = nil
        }
    }

    deinit {
        retryProbeWorkItem?.cancel()
        probeSession.invalidateAndCancel()
        monitor.cancel()
    }
}
