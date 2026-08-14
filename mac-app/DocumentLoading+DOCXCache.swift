import Foundation

extension WebDocumentLoader {
    static func validatedDOCXArchiveEntries(_ entries: [String]) throws -> [String] {
        try DOCXPreparedCache.selectedArchiveEntries(from: entries)
    }

    static func loadPreparedDOCX(
        url: URL,
        cacheRootURL: URL? = nil,
        policy: DOCXPreparedCachePolicy = DOCXPreparedCachePolicy(),
        cancellationToken: DocumentLoadCancellationToken? = nil
    ) throws -> WebReadableDocument {
        try cancellationToken?.checkCancellation()
        let title = url.deletingPathExtension().lastPathComponent
        var measurements: [DocumentLoadMeasurement] = []

        var startedAt = ProcessInfo.processInfo.systemUptime
        let fingerprint = try DOCXPreparedCache.fingerprint(url: url, cancellationToken: cancellationToken)
        measurements.append(measurement(.docxFingerprint, since: startedAt))

        let root: URL
        do {
            root = try DOCXPreparedCache.root(override: cacheRootURL)
        } catch {
            return try loadUncachedStreamingDOCX(
                url: url,
                measurements: measurements,
                cancellationToken: cancellationToken
            )
        }
        let key = DOCXPreparedCache.key(fingerprint: fingerprint, title: title)
        let destination = root.appendingPathComponent(key, isDirectory: true)

        startedAt = ProcessInfo.processInfo.systemUptime
        if FileManager.default.fileExists(atPath: destination.path) {
            do {
                try cancellationToken?.checkCancellation()
                var hitMeasurements = measurements
                hitMeasurements.append(measurement(.docxCacheLookup, since: startedAt))
                let loadStartedAt = ProcessInfo.processInfo.systemUptime
                var document = try DOCXPreparedCache.load(
                    directory: destination,
                    fingerprint: fingerprint,
                    title: title,
                    measurements: hitMeasurements
                )
                document.loadMeasurements.append(measurement(.docxCacheHitLoad, since: loadStartedAt))
                try cancellationToken?.checkCancellation()
                DOCXPreparedCache.cleanup(root: root, keeping: key, policy: policy)
                return document
            } catch {
                if error is CancellationError { throw error }
                try? FileManager.default.removeItem(at: destination)
            }
        }
        measurements.append(measurement(.docxCacheLookup, since: startedAt))

        let temporary = root.appendingPathComponent(
            ".building-\(key)-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            try cancellationToken?.checkCancellation()
            startedAt = ProcessInfo.processInfo.systemUptime
            let archiveEntries = try zipEntryPaths(in: url, cancellationToken: cancellationToken)
            let selectedEntries = try validatedDOCXArchiveEntries(archiveEntries)
            try unzip(
                url: url,
                to: temporary,
                entryPaths: selectedEntries,
                cancellationToken: cancellationToken
            )
            measurements.append(measurement(.docxArchiveExtraction, since: startedAt))

            startedAt = ProcessInfo.processInfo.systemUptime
            let relationships = try docxStreamingRelationships(
                from: temporary.appendingPathComponent("word/_rels/document.xml.rels"),
                cancellationToken: cancellationToken
            )
            measurements.append(measurement(.docxRelationshipParse, since: startedAt))

            startedAt = ProcessInfo.processInfo.systemUptime
            let content = try docxStreamingContent(
                from: temporary.appendingPathComponent("word/document.xml"),
                directory: temporary,
                relationships: relationships,
                mediaReferenceStyle: .relativeToPreparedEntry,
                cancellationToken: cancellationToken
            )
            measurements.append(measurement(.docxXMLRender, since: startedAt))
            try? FileManager.default.removeItem(at: temporary.appendingPathComponent("word/document.xml"))
            try? FileManager.default.removeItem(at: temporary.appendingPathComponent("word/_rels", isDirectory: true))
            try cancellationToken?.checkCancellation()

            startedAt = ProcessInfo.processInfo.systemUptime
            let entryBytes = try DOCXPreparedCache.write(
                directory: temporary,
                fingerprint: fingerprint,
                title: title,
                content: content
            )
            try cancellationToken?.checkCancellation()
            measurements.append(measurement(.docxCacheCommit, since: startedAt))
            if entryBytes > policy.maximumBytes || policy.maximumEntries < 1 {
                let owner = OwnedTemporaryResource(url: temporary)
                return try DOCXPreparedCache.load(
                    directory: temporary,
                    fingerprint: fingerprint,
                    title: title,
                    ownedResource: owner,
                    measurements: measurements
                )
            }

            do {
                try FileManager.default.moveItem(at: temporary, to: destination)
            } catch {
                if FileManager.default.fileExists(atPath: destination.path),
                   let winner = try? DOCXPreparedCache.load(
                    directory: destination,
                    fingerprint: fingerprint,
                    title: title,
                    measurements: measurements
                   ) {
                    try cancellationToken?.checkCancellation()
                    try? FileManager.default.removeItem(at: temporary)
                    DOCXPreparedCache.cleanup(root: root, keeping: key, policy: policy)
                    return winner
                }
                throw error
            }
            DOCXPreparedCache.cleanup(root: root, keeping: key, policy: policy)
            let document = try DOCXPreparedCache.load(
                directory: destination,
                fingerprint: fingerprint,
                title: title,
                measurements: measurements
            )
            try cancellationToken?.checkCancellation()
            return document
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            if error is CancellationError { throw error }
            if (error as NSError).domain == "LeafReader.UnsafeArchive" { throw error }
            return try loadUncachedStreamingDOCX(
                url: url,
                measurements: measurements,
                cancellationToken: cancellationToken
            )
        }
    }

    private static func loadUncachedStreamingDOCX(
        url: URL,
        measurements initialMeasurements: [DocumentLoadMeasurement],
        cancellationToken: DocumentLoadCancellationToken?
    ) throws -> WebReadableDocument {
        var measurements = initialMeasurements
        var startedAt = ProcessInfo.processInfo.systemUptime
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReader-DOCX-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let owner = OwnedTemporaryResource(url: directory)
        do {
            try cancellationToken?.checkCancellation()
            let archiveEntries = try zipEntryPaths(in: url, cancellationToken: cancellationToken)
            let selectedEntries = try validatedDOCXArchiveEntries(archiveEntries)
            try unzip(
                url: url,
                to: directory,
                entryPaths: selectedEntries,
                cancellationToken: cancellationToken
            )
            measurements.append(measurement(.docxArchiveExtraction, since: startedAt))

            startedAt = ProcessInfo.processInfo.systemUptime
            let relationships = try docxStreamingRelationships(
                from: directory.appendingPathComponent("word/_rels/document.xml.rels"),
                cancellationToken: cancellationToken
            )
            measurements.append(measurement(.docxRelationshipParse, since: startedAt))

            startedAt = ProcessInfo.processInfo.systemUptime
            let content = try docxStreamingContent(
                from: directory.appendingPathComponent("word/document.xml"),
                directory: directory,
                relationships: relationships,
                cancellationToken: cancellationToken
            )
            measurements.append(measurement(.docxXMLRender, since: startedAt))
            let title = url.deletingPathExtension().lastPathComponent
            return WebReadableDocument(
                html: pageHTML(
                    title: title,
                    body: content.html.isEmpty
                        ? "<p>\(escapeHTML(AppText.localized("无法读取 DOCX 内容。", "Unable to read DOCX content.")))</p>"
                        : content.html,
                    documentStyles: docxReaderStyles,
                    profile: .docx
                ),
                htmlFileURL: nil,
                baseURL: directory,
                plainText: content.plainText.joined(separator: "\n\n"),
                plainTextLoader: nil,
                coverImageURL: nil,
                tocItems: content.tocItems,
                diagnostics: [],
                ownedResource: owner,
                loadMeasurements: measurements
            )
        } catch {
            owner.release()
            throw error
        }
    }

    private static func measurement(
        _ stage: DocumentLoadStage,
        since startedAt: TimeInterval
    ) -> DocumentLoadMeasurement {
        DocumentLoadMeasurement(
            stage: stage,
            milliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        )
    }
}
