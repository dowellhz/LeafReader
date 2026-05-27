import Foundation

struct LocalRuntimeDownloadManifestAsset: Codable, Equatable {
    let assetName: String
    let byteSize: Int64?
    let sha256: String

    init(assetName: String, byteSize: Int64?, sha256: String) {
        self.assetName = assetName
        self.byteSize = byteSize
        self.sha256 = sha256
    }

    init(name: String, size: Int64?, sha256: String) {
        self.init(assetName: name, byteSize: size, sha256: sha256)
    }

    var name: String {
        assetName
    }

    var size: Int64? {
        byteSize
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case size
        case assetName
        case byteSize
        case sha256
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assetName = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decode(String.self, forKey: .assetName)
        byteSize = try container.decodeIfPresent(Int64.self, forKey: .size)
            ?? container.decodeIfPresent(Int64.self, forKey: .byteSize)
        sha256 = try container.decode(String.self, forKey: .sha256)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(assetName, forKey: .name)
        try container.encodeIfPresent(byteSize, forKey: .size)
        try container.encode(sha256, forKey: .sha256)
    }
}

struct LocalRuntimeDownloadManifest: Decodable, Equatable {
    typealias Asset = LocalRuntimeDownloadManifestAsset

    let generatedAt: String?
    let assets: [Asset]

    func asset(named fileName: String) -> Asset? {
        assets.first { $0.assetName == fileName }
    }
}
