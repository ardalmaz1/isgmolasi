import Foundation

/// Compact descriptors used to recognise duplicate and near-identical images.
///
/// Two complementary signals:
/// - `differenceHash`: a 64-bit perceptual hash. Robust to resizing and recompression
///   (e.g. a WhatsApp copy of an original photo), cheap to compare, but unreliable for
///   near-uniform images (night sky, blank wall) — see `contrast`.
/// - `featureVector`: an L2-normalized image embedding (Vision feature print on device).
///   Better at "same scene, slightly different shot".
public struct VisualFingerprint: Hashable, Sendable {
    public var differenceHash: UInt64?
    /// Luminance standard deviation, 0...1. Low values mean the hash carries little information.
    public var contrast: Double?
    /// Unit-length embedding. `nil` when unavailable.
    public var featureVector: [Float]?

    public init(differenceHash: UInt64? = nil, contrast: Double? = nil, featureVector: [Float]? = nil) {
        self.differenceHash = differenceHash
        self.contrast = contrast
        self.featureVector = featureVector.map(VisualFingerprint.normalized)
    }

    /// Hamming distance between perceptual hashes, if both exist.
    public func hashDistance(to other: VisualFingerprint) -> Int? {
        guard let lhs = differenceHash, let rhs = other.differenceHash else { return nil }
        return (lhs ^ rhs).nonzeroBitCount
    }

    /// Euclidean distance between unit-length embeddings, in 0...2. `nil` if either is missing
    /// or the dimensions differ (e.g. produced by different model revisions).
    public func featureDistance(to other: VisualFingerprint) -> Float? {
        guard let lhs = featureVector, let rhs = other.featureVector, lhs.count == rhs.count, !lhs.isEmpty else {
            return nil
        }
        var sum: Float = 0
        for index in lhs.indices {
            let delta = lhs[index] - rhs[index]
            sum += delta * delta
        }
        return sum.squareRoot()
    }

    static func normalized(_ vector: [Float]) -> [Float] {
        let length = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard length > 0, length.isFinite else { return vector }
        return vector.map { $0 / length }
    }
}

// Custom coding keeps persisted analysis compact: the hash is stored as a hex string (JSON
// numbers are not guaranteed to round-trip 64-bit integers everywhere) and the embedding as
// raw little-endian Float32 bytes instead of hundreds of JSON numbers.
extension VisualFingerprint: Codable {
    private enum CodingKeys: String, CodingKey {
        case differenceHash
        case contrast
        case featureVector
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let hex = try container.decodeIfPresent(String.self, forKey: .differenceHash) {
            differenceHash = UInt64(hex, radix: 16)
        } else {
            differenceHash = nil
        }
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast)
        if let data = try container.decodeIfPresent(Data.self, forKey: .featureVector) {
            featureVector = VisualFingerprint.floats(from: data)
        } else {
            featureVector = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(differenceHash.map { String($0, radix: 16) }, forKey: .differenceHash)
        try container.encodeIfPresent(contrast, forKey: .contrast)
        try container.encodeIfPresent(featureVector.map(VisualFingerprint.data(from:)), forKey: .featureVector)
    }

    static func data(from floats: [Float]) -> Data {
        var data = Data(capacity: floats.count * 4)
        for value in floats {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func floats(from data: Data) -> [Float]? {
        guard data.count % 4 == 0 else { return nil }
        let bytes = [UInt8](data)
        var result = [Float]()
        result.reserveCapacity(bytes.count / 4)
        var index = 0
        while index < bytes.count {
            var bits: UInt32 = UInt32(bytes[index + 3])
            bits = (bits << 8) | UInt32(bytes[index + 2])
            bits = (bits << 8) | UInt32(bytes[index + 1])
            bits = (bits << 8) | UInt32(bytes[index])
            result.append(Float(bitPattern: bits))
            index += 4
        }
        return result
    }
}
