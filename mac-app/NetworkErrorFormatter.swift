import Foundation

enum NetworkErrorFormatter {
    private static let maxBodyCharacters = 4096
    private static let sensitiveKeyPattern = #""(?i)(api[-_ ]?key|authorization|access[-_ ]?token|refresh[-_ ]?token|token|secret)"\s*:\s*"[^"]*""#
    private static let bearerPattern = #"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"#

    static func httpErrorDescription(prefix: String, statusCode: Int, body: String) -> String {
        let sanitizedBody = sanitizedBody(body)
        guard !sanitizedBody.isEmpty else {
            return "\(prefix) HTTP \(statusCode)"
        }
        return "\(prefix) HTTP \(statusCode): \(sanitizedBody)"
    }

    static func sanitizedBody(_ body: String) -> String {
        var value = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        value = value.replacingOccurrences(
            of: sensitiveKeyPattern,
            with: #""$1":"[redacted]""#,
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: bearerPattern,
            with: "Bearer [redacted]",
            options: .regularExpression
        )
        if value.count > maxBodyCharacters {
            value = "\(value.prefix(maxBodyCharacters))..."
        }
        return value
    }
}
