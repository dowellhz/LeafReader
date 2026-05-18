import Foundation

enum EPUBTextDecoder {
    // MARK: - Public API

    static func text(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return text(from: data) ?? String(decoding: data, as: UTF8.self)
    }

    static func text(from data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }

        var encodings: [String.Encoding] = []
        if let declared = declaredTextEncoding(in: data) {
            encodings.append(declared)
        }
        encodings.append(contentsOf: [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            gb18030Encoding,
            .isoLatin1
        ])
        for encoding in uniqueEncodings(encodings) {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        return nil
    }

    // MARK: - Encoding Detection

    private static func declaredTextEncoding(in data: Data) -> String.Encoding? {
        let sample = data.prefix(4096)
        let text = String(data: sample, encoding: .utf8)
            ?? String(data: sample, encoding: .ascii)
            ?? String(data: sample, encoding: .isoLatin1)
            ?? ""
        let patterns = [
            #"(?i)\bencoding\s*=\s*["']([^"']+)["']"#,
            #"(?i)\bcharset\s*=\s*["']?\s*([^"'\s/>;]+)"#
        ]
        for pattern in patterns {
            guard let name = regexMatches(pattern, in: text)
                .first
                .flatMap({ $0.count > 1 ? $0[1] : nil }) else { continue }
            let decodedName = EPUBHTMLSanitizer.decodeEntities(name)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let encoding = stringEncoding(named: decodedName) {
                return encoding
            }
        }
        return nil
    }

    private static func stringEncoding(named name: String) -> String.Encoding? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(normalized as CFString)
        if cfEncoding != kCFStringEncodingInvalidId {
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        }

        switch normalized.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "gbk", "gb2312", "gb18030", "gb-18030":
            return gb18030Encoding
        default:
            return nil
        }
    }

    private static var gb18030Encoding: String.Encoding {
        let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }

    private static func uniqueEncodings(_ encodings: [String.Encoding]) -> [String.Encoding] {
        var seen = Set<UInt>()
        var result: [String.Encoding] = []
        for encoding in encodings where !seen.contains(encoding.rawValue) {
            seen.insert(encoding.rawValue)
            result.append(encoding)
        }
        return result
    }

    // MARK: - Regex

    private static func regexMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return nsText.substring(with: range)
            }
        }
    }
}
