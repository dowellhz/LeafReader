import Foundation

struct EPUBManifestItem: Equatable {
    let id: String
    let href: String
    let mediaType: String
    let properties: Set<String>
}

struct EPUBSpineItem: Equatable {
    let id: String
    let isLinear: Bool
}

struct EPUBPackage {
    let manifestItems: [EPUBManifestItem]
    let manifest: [String: String]
    let spineItems: [EPUBSpineItem]
}

enum EPUBPackageParser {
    // MARK: - Public API

    static func package(from xml: String) -> EPUBPackage {
        let parsed = opfParse(xml)
        let manifestItems = parsed.manifestItems.isEmpty ? manifestItemsByRegex(from: xml) : parsed.manifestItems
        let spineItems = parsed.spineItems.isEmpty ? spineItemsByRegex(from: xml) : parsed.spineItems
        return EPUBPackage(
            manifestItems: manifestItems,
            manifest: manifest(from: manifestItems),
            spineItems: spineItems
        )
    }

    static func spineItemsByRegex(from xml: String) -> [EPUBSpineItem] {
        regexMatches(#"<itemref\b[^>]*?/?>"#, in: xml).compactMap { match in
            guard let tag = match.first,
                  let id = firstXMLAttribute("idref", in: tag) else { return nil }
            let linear = (firstXMLAttribute("linear", in: tag) ?? "yes")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return EPUBSpineItem(id: id, isLinear: linear != "no")
        }
    }

    // MARK: - Parsed Manifest

    private static func manifest(from items: [EPUBManifestItem]) -> [String: String] {
        var result: [String: String] = [:]
        for item in items where result[item.id] == nil {
            result[item.id] = item.href
        }
        return result
    }

    // MARK: - XML Parser

    private static func opfParse(_ xml: String) -> (manifestItems: [EPUBManifestItem], spineItems: [EPUBSpineItem]) {
        guard let data = xml.data(using: .utf8) else { return ([], []) }
        let delegate = EPUBOPFParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return ([], []) }
        return (delegate.manifestItems, delegate.spineItems)
    }

    // MARK: - Regex Fallback

    private static func manifestItemsByRegex(from xml: String) -> [EPUBManifestItem] {
        regexMatches(#"<item\b[^>]*?/?>"#, in: xml).compactMap { match in
            guard let tag = match.first,
                  let id = firstXMLAttribute("id", in: tag),
                  let href = firstXMLAttribute("href", in: tag) else { return nil }
            let properties = Set((firstXMLAttribute("properties", in: tag) ?? "")
                .lowercased()
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init))
            return EPUBManifestItem(
                id: id,
                href: href,
                mediaType: (firstXMLAttribute("media-type", in: tag) ?? "").lowercased(),
                properties: properties
            )
        }
    }

    private static func regexMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return nsText.substring(with: range)
            }
        }
    }

    private static func firstXMLAttribute(_ attribute: String, in xml: String) -> String? {
        let pattern = #"\#(attribute)=["']([^"']+)["']"#
        return regexMatches(pattern, in: xml).first.flatMap { $0.count > 1 ? $0[1] : nil }
    }
}

private final class EPUBOPFParser: NSObject, XMLParserDelegate {
    private(set) var manifestItems: [EPUBManifestItem] = []
    private(set) var spineItems: [EPUBSpineItem] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = (qName ?? elementName).split(separator: ":").last.map(String.init) ?? elementName
        switch name {
        case "item":
            guard let id = attributeDict["id"],
                  let href = attributeDict["href"] else { return }
            let properties = Set((attributeDict["properties"] ?? "")
                .lowercased()
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init))
            manifestItems.append(EPUBManifestItem(
                id: id,
                href: href,
                mediaType: (attributeDict["media-type"] ?? "").lowercased(),
                properties: properties
            ))
        case "itemref":
            guard let id = attributeDict["idref"] else { return }
            let linear = (attributeDict["linear"] ?? "yes")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            spineItems.append(EPUBSpineItem(id: id, isLinear: linear != "no"))
        default:
            break
        }
    }
}
