import Foundation

enum LocalRuntimeFamily: String, Equatable {
    case speech
    case localLLM
}

struct LocalRuntimeDescriptor {
    let family: LocalRuntimeFamily
    let id: String
    let title: String
    let summaryText: String
    let downloadSizeText: String
    let minimumSystemVersion: OperatingSystemVersion
    let minimumSystemVersionText: String
    let downloadURL: URL
    let manifestURL: URL?
    let installDirectory: URL
    let bundledInstallDirectory: URL?
    let installDirectories: [URL]
    let executableURL: URL
    let bundledExecutableURL: URL?
    let modelDirectory: URL
    let requiredPaths: [URL]
}
