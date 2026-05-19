import Foundation

enum UpdateFailureKind: Equatable {
    case certificate
    case network
    case appcast
    case other
}

enum UpdateFailureClassifier {
    static func classify(_ error: NSError) -> UpdateFailureKind {
        let errors = flattenedErrors(from: error)
        if containsCertificateError(errors) {
            return .certificate
        }
        if containsNetworkConnectionError(errors) {
            return .network
        }
        if containsAppcastReadError(errors) {
            return .appcast
        }
        return .other
    }

    private static func flattenedErrors(from error: NSError) -> [NSError] {
        var errors = [error]
        var cursor: NSError? = error
        while let nestedError = cursor?.userInfo[NSUnderlyingErrorKey] as? NSError {
            errors.append(nestedError)
            cursor = nestedError
        }
        return errors
    }

    private static func containsCertificateError(_ errors: [NSError]) -> Bool {
        let certificateCodes = [
            NSURLErrorSecureConnectionFailed,
            NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateUntrusted,
            NSURLErrorServerCertificateHasUnknownRoot,
            NSURLErrorServerCertificateNotYetValid,
            NSURLErrorClientCertificateRejected,
            NSURLErrorClientCertificateRequired
        ]
        return errors.contains { error in
            if error.domain == NSURLErrorDomain, certificateCodes.contains(error.code) {
                return true
            }
            let text = searchableText(error)
            return text.contains("ssl") || text.contains("certificate") || text.contains("cert")
        }
    }

    private static func containsNetworkConnectionError(_ errors: [NSError]) -> Bool {
        let connectionCodes = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorDataNotAllowed
        ]
        return errors.contains { error in
            error.domain == NSURLErrorDomain && connectionCodes.contains(error.code)
        }
    }

    private static func containsAppcastReadError(_ errors: [NSError]) -> Bool {
        errors.contains { error in
            let text = searchableText(error)
            return text.contains("appcast")
                || text.contains("feed")
                || text.contains("xml")
                || text.contains("parse")
                || text.contains("decode")
        }
    }

    private static func searchableText(_ error: NSError) -> String {
        [
            error.domain,
            error.localizedDescription,
            error.localizedFailureReason,
            error.localizedRecoverySuggestion
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }
}
