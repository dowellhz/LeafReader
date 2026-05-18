import Foundation

enum EPUBPathResolver {
    private struct HrefParts {
        let path: String
        let fragment: String
    }

    static func safeArchivePath(_ path: String) -> String? {
        let standardized = (path as NSString).standardizingPath
        let components = standardized.split(separator: "/").map(String.init)
        guard !standardized.isEmpty,
              !standardized.hasPrefix("/"),
              standardized != ".",
              standardized != "..",
              !standardized.hasPrefix("../"),
              !components.contains("..") else {
            return nil
        }
        return standardized
    }

    static func normalizedTOCHref(_ href: String, relativeTo baseHref: String) -> String {
        let decodedHref = EPUBHTMLSanitizer.decodeEntities(href).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decodedHref.isEmpty else { return decodedHref }
        let hrefParts = splitHref(decodedHref)
        let baseDirectory = URL(fileURLWithPath: baseHref).deletingLastPathComponent().relativePath
        let joined: String
        if hrefParts.path.isEmpty {
            joined = ""
        } else if hrefParts.path.hasPrefix("/") || baseDirectory == "." {
            joined = hrefParts.path
        } else {
            joined = "\(baseDirectory)/\(hrefParts.path)"
        }
        let normalizedPath = normalizedRelativePath(joined)
        let path = normalizedPath == "." ? "" : normalizedPath
        return hrefWithFragment(path: path, fragment: hrefParts.fragment)
    }

    static func internalLinkTarget(_ href: String, resourceBaseURL: URL, documentBaseURL: URL, epubRootURL: URL) -> String? {
        let decodedHref = EPUBHTMLSanitizer.decodeEntities(href).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decodedHref.isEmpty,
              !decodedHref.lowercased().hasPrefix("data:") else { return nil }
        let hrefParts = splitHref(decodedHref)
        let resourceURL = hrefParts.path.isEmpty ? resourceBaseURL : resourceBaseURL.appendingPathComponent(hrefParts.path).standardizedFileURL
        guard isFileURL(resourceURL, containedIn: epubRootURL) else { return nil }
        let path = hrefParts.path.isEmpty ? "" : relativeFilePath(from: documentBaseURL.standardizedFileURL, to: resourceURL)
        guard !path.isEmpty || !hrefParts.fragment.isEmpty else { return nil }
        return hrefWithFragment(path: path, fragment: hrefParts.fragment)
    }

    static func resourcePath(_ href: String, resourceBaseURL: URL, documentBaseURL: URL, epubRootURL: URL, allowedCharacters: CharacterSet) -> String? {
        let hrefWithoutFragment = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? href
        guard !hrefWithoutFragment.isEmpty,
              !hrefWithoutFragment.lowercased().hasPrefix("data:") else { return nil }
        let decodedHref = hrefWithoutFragment.removingPercentEncoding ?? hrefWithoutFragment
        let resourceURL = resourceBaseURL.appendingPathComponent(decodedHref).standardizedFileURL
        guard isFileURL(resourceURL, containedIn: epubRootURL) else { return nil }
        return relativeFilePath(from: documentBaseURL.standardizedFileURL, to: resourceURL)
            .addingPercentEncoding(withAllowedCharacters: allowedCharacters)
    }

    static func isFileURL(_ url: URL, containedIn rootURL: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/")
    }

    static func relativeFilePath(from baseURL: URL, to resourceURL: URL) -> String {
        let baseComponents = baseURL.standardizedFileURL.pathComponents
        let resourceComponents = resourceURL.standardizedFileURL.pathComponents
        var commonCount = 0
        while commonCount < baseComponents.count,
              commonCount < resourceComponents.count,
              baseComponents[commonCount] == resourceComponents[commonCount] {
            commonCount += 1
        }
        let parentSegments = Array(repeating: "..", count: max(0, baseComponents.count - commonCount))
        let resourceSegments = Array(resourceComponents.dropFirst(commonCount))
        let path = (parentSegments + resourceSegments).joined(separator: "/")
        return path.isEmpty ? resourceURL.lastPathComponent : path
    }

    static func normalizedRelativePath(_ path: String) -> String {
        let isAbsolute = path.hasPrefix("/")
        var components: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            if component == "." {
                continue
            }
            if component == ".." {
                if !components.isEmpty, components.last != ".." {
                    components.removeLast()
                } else if !isAbsolute {
                    components.append(component)
                }
            } else {
                components.append(component)
            }
        }
        let normalized = components.joined(separator: "/")
        if isAbsolute {
            return normalized.isEmpty ? "/" : "/\(normalized)"
        }
        return normalized.isEmpty ? "." : normalized
    }

    private static func splitHref(_ href: String) -> HrefParts {
        let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = parts.first.map(String.init) ?? ""
        let rawFragment = parts.count > 1 ? String(parts[1]) : ""
        let pathWithoutQuery = rawPath
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? rawPath
        return HrefParts(
            path: pathWithoutQuery.removingPercentEncoding ?? pathWithoutQuery,
            fragment: rawFragment.removingPercentEncoding ?? rawFragment
        )
    }

    private static func hrefWithFragment(path: String, fragment: String) -> String {
        guard !fragment.isEmpty else { return path }
        return path.isEmpty ? "#\(fragment)" : "\(path)#\(fragment)"
    }
}
