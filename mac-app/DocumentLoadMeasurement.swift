import Foundation

enum DocumentLoadStage: String, Codable {
    case docxFingerprint
    case docxCacheLookup
    case docxArchiveExtraction
    case docxRelationshipParse
    case docxXMLRender
    case docxCacheCommit
    case docxCacheHitLoad
}

struct DocumentLoadMeasurement: Equatable {
    let stage: DocumentLoadStage
    let milliseconds: Double
}
