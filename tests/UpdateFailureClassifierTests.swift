import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) throws {
    if lhs != rhs {
        throw TestFailure(description: "\(message). expected \(rhs), got \(lhs)")
    }
}

private func testCertificateURLFailureIsClassified() throws {
    let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted)
    try expectEqual(
        UpdateFailureClassifier.classify(error),
        .certificate,
        "certificate URL errors should be classified as certificate failures"
    )
}

private func testNestedCertificateFailureIsClassified() throws {
    let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed)
    let wrapper = NSError(
        domain: "Sparkle",
        code: 1,
        userInfo: [NSUnderlyingErrorKey: underlying]
    )
    try expectEqual(
        UpdateFailureClassifier.classify(wrapper),
        .certificate,
        "nested certificate URL errors should be classified as certificate failures"
    )
}

private func testNetworkFailureIsClassified() throws {
    let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
    try expectEqual(
        UpdateFailureClassifier.classify(error),
        .network,
        "host lookup failures should be classified as network failures"
    )
}

private func testAppcastFailureIsClassifiedFromText() throws {
    let error = NSError(
        domain: "Sparkle",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Unable to parse appcast XML feed"]
    )
    try expectEqual(
        UpdateFailureClassifier.classify(error),
        .appcast,
        "appcast parse failures should be classified as appcast failures"
    )
}

private func testUnknownFailureFallsBackToOther() throws {
    let error = NSError(domain: "LeafReaderTests", code: 99)
    try expectEqual(
        UpdateFailureClassifier.classify(error),
        .other,
        "unknown errors should remain generic"
    )
}

@main
struct UpdateFailureClassifierTestRunner {
    static func main() {
        do {
            try testCertificateURLFailureIsClassified()
            print("PASS update certificate classification")
            try testNestedCertificateFailureIsClassified()
            print("PASS update nested certificate classification")
            try testNetworkFailureIsClassified()
            print("PASS update network classification")
            try testAppcastFailureIsClassifiedFromText()
            print("PASS update appcast classification")
            try testUnknownFailureFallsBackToOther()
            print("PASS update generic fallback classification")
            print("UpdateFailureClassifierTests passed")
        } catch {
            fputs("UpdateFailureClassifierTests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
