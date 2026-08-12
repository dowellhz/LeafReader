import Foundation

struct ArchiveSafetyPolicy {
    let maximumEntries: Int
    let maximumSingleFileBytes: Int64
    let maximumExpandedBytes: Int64
    let maximumCompressionRatio: Double
    let allowsContainedSymlinks: Bool

    init(
        maximumEntries: Int,
        maximumSingleFileBytes: Int64,
        maximumExpandedBytes: Int64,
        maximumCompressionRatio: Double,
        allowsContainedSymlinks: Bool = false
    ) {
        self.maximumEntries = maximumEntries
        self.maximumSingleFileBytes = maximumSingleFileBytes
        self.maximumExpandedBytes = maximumExpandedBytes
        self.maximumCompressionRatio = maximumCompressionRatio
        self.allowsContainedSymlinks = allowsContainedSymlinks
    }

    static let document = ArchiveSafetyPolicy(
        maximumEntries: 20_000,
        maximumSingleFileBytes: 1_073_741_824,
        maximumExpandedBytes: 2_147_483_648,
        maximumCompressionRatio: 200
    )

    static let runtime = ArchiveSafetyPolicy(
        maximumEntries: 100_000,
        maximumSingleFileBytes: 8_589_934_592,
        maximumExpandedBytes: 17_179_869_184,
        maximumCompressionRatio: 250,
        allowsContainedSymlinks: true
    )
}

enum ArchiveSafetyValidator {
    private static let zipCentralHeader: UInt32 = 0x02014b50
    private static let zipEndOfCentralDirectory: UInt32 = 0x06054b50
    private static let zip64UInt16 = UInt16.max
    private static let zip64UInt32 = UInt32.max

    static func validateZIP(at url: URL, policy: ArchiveSafetyPolicy = .document) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let directory = try zipCentralDirectory(in: data)
        guard directory.entryCount <= policy.maximumEntries else {
            throw unsafeArchive("Archive contains too many entries.")
        }

        var cursor = directory.offset
        var paths = Set<String>()
        var expandedBytes: Int64 = 0
        var compressedBytes: Int64 = 0
        for _ in 0..<directory.entryCount {
            guard data.uint32LE(at: cursor) == zipCentralHeader else {
                throw unsafeArchive("Archive central directory is malformed.")
            }
            let flags = try data.requiredUInt16LE(at: cursor + 8)
            let compressed = Int64(try data.requiredUInt32LE(at: cursor + 20))
            let expanded = Int64(try data.requiredUInt32LE(at: cursor + 24))
            let nameLength = Int(try data.requiredUInt16LE(at: cursor + 28))
            let extraLength = Int(try data.requiredUInt16LE(at: cursor + 30))
            let commentLength = Int(try data.requiredUInt16LE(at: cursor + 32))
            let externalAttributes = try data.requiredUInt32LE(at: cursor + 38)
            guard compressed != Int64(zip64UInt32), expanded != Int64(zip64UInt32) else {
                throw unsafeArchive("ZIP64 archives exceed the supported document safety limits.")
            }
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= data.count else {
                throw unsafeArchive("Archive entry name is truncated.")
            }
            let nameData = data.subdata(in: nameStart..<nameEnd)
            guard let rawPath = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1) else {
                throw unsafeArchive("Archive entry name is not decodable.")
            }
            let path = try validatedRelativePath(rawPath)
            guard paths.insert(path).inserted else {
                throw unsafeArchive("Archive contains duplicate paths.")
            }
            guard flags & 0x1 == 0 else {
                throw unsafeArchive("Encrypted archive entries are not supported.")
            }
            let unixMode = (externalAttributes >> 16) & 0xF000
            guard unixMode != 0xA000 else {
                throw unsafeArchive("Archive symbolic links are not allowed.")
            }
            guard unixMode == 0 || unixMode == 0x4000 || unixMode == 0x8000 else {
                throw unsafeArchive("Archive special files are not allowed.")
            }
            try accumulate(
                expanded: expanded,
                compressed: compressed,
                expandedTotal: &expandedBytes,
                policy: policy
            )
            compressedBytes += compressed
            cursor = nameEnd + extraLength + commentLength
            guard cursor <= directory.offset + directory.size, cursor <= data.count else {
                throw unsafeArchive("Archive central directory entry exceeds its bounds.")
            }
        }
        guard cursor == directory.offset + directory.size else {
            throw unsafeArchive("Archive central directory size does not match its entries.")
        }
        try validateRatio(expanded: expandedBytes, compressed: compressedBytes, policy: policy)
    }

    static func validateTarGzipListing(
        pathsOutput: Data,
        verboseOutput: Data,
        compressedArchiveBytes: Int64? = nil,
        policy: ArchiveSafetyPolicy = .runtime
    ) throws {
        guard let pathsText = String(data: pathsOutput, encoding: .utf8),
              let verboseText = String(data: verboseOutput, encoding: .utf8) else {
            throw unsafeArchive("Archive listing is not valid UTF-8.")
        }
        let paths = nonEmptyLines(pathsText)
        let verboseLines = nonEmptyLines(verboseText)
        guard paths.count == verboseLines.count else {
            throw unsafeArchive("Archive listing is inconsistent.")
        }
        guard paths.count <= policy.maximumEntries else {
            throw unsafeArchive("Archive contains too many entries.")
        }

        var uniquePaths = Set<String>()
        var expandedBytes: Int64 = 0
        for (path, verboseLine) in zip(paths, verboseLines) {
            let normalized = try validatedRelativePath(path)
            guard uniquePaths.insert(normalized).inserted else {
                throw unsafeArchive("Archive contains duplicate paths.")
            }
            guard let mode = verboseLine.first else {
                throw unsafeArchive("Archive entry metadata is missing.")
            }
            if mode == "l" {
                guard policy.allowsContainedSymlinks,
                      let target = verboseLine.components(separatedBy: " -> ").last,
                      target != verboseLine,
                      isContainedLinkTarget(target, from: normalized) else {
                    throw unsafeArchive("Archive symbolic link escapes its destination.")
                }
            } else if mode != "-" && mode != "d" {
                throw unsafeArchive("Archive links and special files are not allowed.")
            }
            let size = try tarEntrySize(from: verboseLine)
            try accumulate(
                expanded: size,
                compressed: max(size, 1),
                expandedTotal: &expandedBytes,
                policy: policy
            )
        }
        if let compressedArchiveBytes {
            try validateRatio(
                expanded: expandedBytes,
                compressed: compressedArchiveBytes,
                policy: policy
            )
        }
    }

    static func validateExtractedTree(
        at root: URL,
        policy: ArchiveSafetyPolicy
    ) throws {
        let fileManager = FileManager.default
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey],
            options: []
        ) else {
            throw unsafeArchive("Unable to inspect extracted archive.")
        }
        var entries = 0
        var expandedBytes: Int64 = 0
        for case let itemURL as URL in enumerator {
            entries += 1
            guard entries <= policy.maximumEntries else {
                throw unsafeArchive("Extracted archive contains too many entries.")
            }
            let values = try itemURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            guard values.isSymbolicLink != true || policy.allowsContainedSymlinks else {
                throw unsafeArchive("Extracted archive contains a symbolic link.")
            }
            let resolvedPath = itemURL.standardizedFileURL.resolvingSymlinksInPath().path
            guard isPath(resolvedPath, containedIn: rootPath) else {
                throw unsafeArchive("Extracted archive escaped its destination.")
            }
            if values.isRegularFile == true {
                let size = Int64(values.fileSize ?? 0)
                try accumulate(
                    expanded: size,
                    compressed: max(size, 1),
                    expandedTotal: &expandedBytes,
                    policy: policy
                )
            }
        }
    }

    static func validatedRelativePath(_ rawPath: String) throws -> String {
        guard !rawPath.isEmpty, !rawPath.contains("\0") else {
            throw unsafeArchive("Archive contains an empty or invalid path.")
        }
        let normalized = rawPath.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/"),
              normalized.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil else {
            throw unsafeArchive("Archive contains an absolute path.")
        }
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(where: { $0 == ".." }) else {
            throw unsafeArchive("Archive contains parent-directory traversal.")
        }
        let safePath = components.filter { !$0.isEmpty && $0 != "." }.joined(separator: "/")
        guard !safePath.isEmpty else {
            throw unsafeArchive("Archive contains an empty path.")
        }
        return safePath
    }

    private static func zipCentralDirectory(in data: Data) throws -> (offset: Int, size: Int, entryCount: Int) {
        let minimumOffset = max(0, data.count - 65_557)
        guard data.count >= 22 else { throw unsafeArchive("Archive is truncated.") }
        var cursor = data.count - 22
        while cursor >= minimumOffset {
            if data.uint32LE(at: cursor) == zipEndOfCentralDirectory {
                let disk = try data.requiredUInt16LE(at: cursor + 4)
                let directoryDisk = try data.requiredUInt16LE(at: cursor + 6)
                let diskEntries = try data.requiredUInt16LE(at: cursor + 8)
                let totalEntries = try data.requiredUInt16LE(at: cursor + 10)
                let size = try data.requiredUInt32LE(at: cursor + 12)
                let offset = try data.requiredUInt32LE(at: cursor + 16)
                guard disk == 0, directoryDisk == 0, diskEntries == totalEntries else {
                    throw unsafeArchive("Multi-disk archives are not supported.")
                }
                guard totalEntries != zip64UInt16, size != zip64UInt32, offset != zip64UInt32 else {
                    throw unsafeArchive("ZIP64 archives exceed the supported document safety limits.")
                }
                let intOffset = Int(offset)
                let intSize = Int(size)
                guard intOffset >= 0, intSize >= 0, intOffset + intSize <= cursor else {
                    throw unsafeArchive("Archive central directory is outside the file.")
                }
                return (intOffset, intSize, Int(totalEntries))
            }
            if cursor == 0 { break }
            cursor -= 1
        }
        throw unsafeArchive("Archive central directory was not found.")
    }

    private static func tarEntrySize(from line: String) throws -> Int64 {
        let pattern = #"^[^\s]+\s+\d+\s+\S+\s+\S+\s+(\d+)\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line),
              let size = Int64(line[range]) else {
            throw unsafeArchive("Archive entry metadata is malformed.")
        }
        return size
    }

    private static func accumulate(
        expanded: Int64,
        compressed: Int64,
        expandedTotal: inout Int64,
        policy: ArchiveSafetyPolicy
    ) throws {
        guard expanded >= 0, compressed >= 0, expanded <= policy.maximumSingleFileBytes else {
            throw unsafeArchive("Archive entry exceeds the size limit.")
        }
        guard expandedTotal <= policy.maximumExpandedBytes - expanded else {
            throw unsafeArchive("Archive exceeds the expanded size limit.")
        }
        expandedTotal += expanded
        if compressed > 0, expanded > 1_048_576 {
            try validateRatio(expanded: expanded, compressed: compressed, policy: policy)
        }
    }

    private static func validateRatio(expanded: Int64, compressed: Int64, policy: ArchiveSafetyPolicy) throws {
        let divisor = max(compressed, 1)
        guard Double(expanded) / Double(divisor) <= policy.maximumCompressionRatio else {
            throw unsafeArchive("Archive compression ratio exceeds the safety limit.")
        }
    }

    private static func nonEmptyLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }

    private static func isPath(_ path: String, containedIn root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    private static func isContainedLinkTarget(_ target: String, from linkPath: String) -> Bool {
        guard !target.hasPrefix("/"),
              target.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil else {
            return false
        }
        let root = URL(fileURLWithPath: "/leafreader-archive-root", isDirectory: true)
        let linkDirectory = root
            .appendingPathComponent(linkPath)
            .deletingLastPathComponent()
        let resolved = linkDirectory
            .appendingPathComponent(target)
            .standardizedFileURL
        return isPath(resolved.path, containedIn: root.path)
    }

    private static func unsafeArchive(_ message: String) -> NSError {
        NSError(
            domain: "LeafReader.UnsafeArchive",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: AppText.localized("压缩包不安全或超出资源限制。", message)]
        )
    }
}

private extension Data {
    func uint32LE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let byte0 = UInt32(self[index(startIndex, offsetBy: offset)])
        let byte1 = UInt32(self[index(startIndex, offsetBy: offset + 1)]) << 8
        let byte2 = UInt32(self[index(startIndex, offsetBy: offset + 2)]) << 16
        let byte3 = UInt32(self[index(startIndex, offsetBy: offset + 3)]) << 24
        return byte0 | byte1 | byte2 | byte3
    }

    func requiredUInt16LE(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else {
            throw NSError(domain: "LeafReader.UnsafeArchive", code: -1)
        }
        let byte0 = UInt16(self[index(startIndex, offsetBy: offset)])
        let byte1 = UInt16(self[index(startIndex, offsetBy: offset + 1)]) << 8
        return byte0 | byte1
    }

    func requiredUInt32LE(at offset: Int) throws -> UInt32 {
        guard let value = uint32LE(at: offset) else {
            throw NSError(domain: "LeafReader.UnsafeArchive", code: -1)
        }
        return value
    }
}
