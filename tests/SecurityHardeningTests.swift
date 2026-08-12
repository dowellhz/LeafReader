import Foundation

enum SecurityHardeningTests {
    static func testArchivePathsAndZIPValidation() throws {
        try expectThrows("parent traversal should be rejected") {
            _ = try ArchiveSafetyValidator.validatedRelativePath("OPS/../../outside")
        }
        try expectThrows("absolute paths should be rejected") {
            _ = try ArchiveSafetyValidator.validatedRelativePath("/private/tmp/outside")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-archive-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let safeFile = root.appendingPathComponent("safe.txt")
        try Data("safe".utf8).write(to: safeFile)
        let safeArchive = root.appendingPathComponent("safe.zip")
        try runArchiveCommand("/usr/bin/zip", ["-q", safeArchive.path, "safe.txt"], in: root)
        try ArchiveSafetyValidator.validateZIP(at: safeArchive)

        let link = root.appendingPathComponent("escape-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/private/tmp"))
        let linkArchive = root.appendingPathComponent("link.zip")
        try runArchiveCommand("/usr/bin/zip", ["-q", "-y", linkArchive.path, "escape-link"], in: root)
        try expectThrows("ZIP symbolic links should be rejected") {
            try ArchiveSafetyValidator.validateZIP(at: linkArchive)
        }

        let compressedFile = root.appendingPathComponent("compressed.txt")
        try Data(repeating: 0, count: 2_000_000).write(to: compressedFile)
        let compressedArchive = root.appendingPathComponent("compressed.zip")
        try runArchiveCommand("/usr/bin/zip", ["-q", compressedArchive.path, "compressed.txt"], in: root)
        let strictPolicy = ArchiveSafetyPolicy(
            maximumEntries: 10,
            maximumSingleFileBytes: 3_000_000,
            maximumExpandedBytes: 3_000_000,
            maximumCompressionRatio: 5
        )
        try expectThrows("unsafe ZIP compression ratios should be rejected") {
            try ArchiveSafetyValidator.validateZIP(at: compressedArchive, policy: strictPolicy)
        }
    }

    static func testRuntimeArchiveListingValidation() throws {
        let safePaths = Data("Runtime/bin/tool\nRuntime/Models/model.bin\n".utf8)
        let safeVerboseText =
            "-rwxr-xr-x  0 user group 1024 Jan 1 00:00 Runtime/bin/tool\n" +
            "-rw-r--r--  0 user group 2048 Jan 1 00:00 Runtime/Models/model.bin\n"
        let safeVerbose = Data(safeVerboseText.utf8)
        try ArchiveSafetyValidator.validateTarGzipListing(
            pathsOutput: safePaths,
            verboseOutput: safeVerbose
        )
        try ArchiveSafetyValidator.validateTarGzipListing(
            pathsOutput: Data("Runtime/bin/tool-link\n".utf8),
            verboseOutput: Data("lrwxr-xr-x  0 user group 0 Jan 1 00:00 Runtime/bin/tool-link -> ../lib/tool\n".utf8)
        )

        try expectThrows("tar traversal should be rejected") {
            try ArchiveSafetyValidator.validateTarGzipListing(
                pathsOutput: Data("../outside\n".utf8),
                verboseOutput: Data("-rw-r--r--  0 user group 1 Jan 1 00:00 ../outside\n".utf8)
            )
        }
        try expectThrows("tar symbolic links should be rejected") {
            try ArchiveSafetyValidator.validateTarGzipListing(
                pathsOutput: Data("Runtime/link\n".utf8),
                verboseOutput: Data("lrwxr-xr-x  0 user group 0 Jan 1 00:00 Runtime/link -> /tmp\n".utf8)
            )
        }
        let strictPolicy = ArchiveSafetyPolicy(
            maximumEntries: 10,
            maximumSingleFileBytes: 10_000,
            maximumExpandedBytes: 10_000,
            maximumCompressionRatio: 5
        )
        try expectThrows("unsafe tar compression ratios should be rejected") {
            try ArchiveSafetyValidator.validateTarGzipListing(
                pathsOutput: safePaths,
                verboseOutput: safeVerbose,
                compressedArchiveBytes: 1,
                policy: strictPolicy
            )
        }
    }

    static func testTemporaryResourceLifecycleAndContentCacheIdentity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-resource-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let ownedDirectory = root.appendingPathComponent("owned", isDirectory: true)
        try FileManager.default.createDirectory(at: ownedDirectory, withIntermediateDirectories: true)
        let owner = OwnedTemporaryResource(url: ownedDirectory)
        owner.release()

        let extractedDirectory = root.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: extractedDirectory.appendingPathComponent("escape"),
            withDestinationURL: URL(fileURLWithPath: "/private/tmp")
        )
        try expectThrows("post-extraction symlinks should be rejected") {
            try ArchiveSafetyValidator.validateExtractedTree(at: extractedDirectory, policy: .document)
        }
        try expect(!FileManager.default.fileExists(atPath: ownedDirectory.path), "explicit release should remove an owned temporary directory")
        owner.release()

        let document = root.appendingPathComponent("book.epub")
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try Data("AAAA".utf8).write(to: document)
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: document.path)
        let firstKey = try DocumentContentIdentity.sha256Key(for: document)
        try Data("BBBB".utf8).write(to: document)
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: document.path)
        let secondKey = try DocumentContentIdentity.sha256Key(for: document)
        try expect(firstKey != secondKey, "EPUB cache identity should change when equal-size content changes with the same mtime")
    }

    static func testWebDocumentSecurityPolicy() throws {
        let csp = WebDocumentSecurityPolicy.contentSecurityPolicy
        try expect(csp.contains("default-src 'none'"), "reader CSP should deny unspecified resources")
        try expect(csp.contains("connect-src 'none'"), "reader CSP should prevent document network connections")
        try expect(csp.contains("form-action 'none'"), "reader CSP should prevent form submission")
        let script = WebDocumentSecurityPolicy.DOMSanitizerScript
        try expect(script.contains("allowedTags"), "reader DOM sanitizer should use an element allowlist")
        try expect(script.contains("srcset"), "reader DOM sanitizer should remove srcset remote-resource bypasses")
        try expect(script.contains("@import"), "reader DOM sanitizer should reject CSS URL import paths")

        let external = URL(string: "https://example.com/track")!
        try expectEqual(
            WebDocumentNavigationPolicy.decision(for: external, isUserActivatedLink: false, isApprovedInitialNavigation: false),
            .cancel,
            "non-user external navigation such as meta refresh should be rejected"
        )
        try expectEqual(
            WebDocumentNavigationPolicy.decision(for: external, isUserActivatedLink: true, isApprovedInitialNavigation: false),
            .openExternally,
            "explicit external links should open outside the reader"
        )
        let formTarget = URL(string: "file:///tmp/submitted")!
        try expectEqual(
            WebDocumentNavigationPolicy.decision(for: formTarget, isUserActivatedLink: false, isApprovedInitialNavigation: false),
            .cancel,
            "form-style local navigation should be rejected"
        )
        let internalLink = URL(string: "file:///tmp/book.xhtml#note")!
        try expectEqual(
            WebDocumentNavigationPolicy.decision(for: internalLink, isUserActivatedLink: true, isApprovedInitialNavigation: false),
            .scrollToFragment("note"),
            "internal anchors should remain usable"
        )
        try expectEqual(
            WebDocumentNavigationPolicy.decision(for: formTarget, isUserActivatedLink: false, isApprovedInitialNavigation: true),
            .allow,
            "the controller-approved initial local load should be allowed"
        )
    }

    private static func runArchiveCommand(_ executable: String, _ arguments: [String], in directory: URL) throws {
        let result = try ProcessRunner.run(
            executableURL: URL(fileURLWithPath: executable),
            arguments: arguments,
            timeout: 15,
            currentDirectoryURL: directory
        )
        guard !result.timedOut, result.terminationStatus == 0 else {
            throw TestFailure(description: "archive fixture command failed")
        }
    }

    private static func expectThrows(_ message: String, operation: () throws -> Void) throws {
        do {
            try operation()
            throw TestFailure(description: message)
        } catch is TestFailure {
            throw TestFailure(description: message)
        } catch {
            return
        }
    }
}
