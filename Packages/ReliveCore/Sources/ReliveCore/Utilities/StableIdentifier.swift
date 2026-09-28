import Foundation

/// Deterministic UUIDs derived from a string key.
///
/// Regenerating a story from the same assets produces the same moment ids, which keeps user
/// state attached and makes the engine's output reproducible in tests. Foundation has no
/// portable hash digest, so this uses two independent 64-bit FNV-1a passes finished with a
/// SplitMix64 avalanche. It is not cryptographic — it only needs to be stable and well spread.
enum StableIdentifier {
    static func uuid(namespace: String, key: String) -> UUID {
        let bytes = Array("\(namespace):\(key)".utf8)
        let high = mix(fnv1a(bytes, seed: 0xcbf2_9ce4_8422_2325))
        let low = mix(fnv1a(bytes, seed: 0x8422_2325_cbf2_9ce4) ^ UInt64(bytes.count))

        var raw = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            raw[index] = UInt8(truncatingIfNeeded: high >> (56 - 8 * UInt64(index)))
            raw[index + 8] = UInt8(truncatingIfNeeded: low >> (56 - 8 * UInt64(index)))
        }
        // Mark as a name-based (version 5 layout) RFC 4122 UUID.
        raw[6] = (raw[6] & 0x0F) | 0x50
        raw[8] = (raw[8] & 0x3F) | 0x80

        return UUID(uuid: (
            raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
            raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]
        ))
    }

    private static func fnv1a(_ bytes: [UInt8], seed: UInt64) -> UInt64 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    private static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
