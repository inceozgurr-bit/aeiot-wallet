import Foundation

/// Bech32 / bech32m, the encoding behind Bitcoin's bc1… addresses. It carries
/// its own checksum, so a mistyped address fails to decode rather than sending
/// coins into the void.
enum Bech32 {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let generator: [UInt32] = [0x3b6a_57b2, 0x2650_8e6d, 0x1ea1_19fa, 0x3d42_33dd, 0x2a14_62b3]

    private enum Variant {
        case bech32, bech32m
        var constant: UInt32 { self == .bech32 ? 1 : 0x2bc8_30a3 }
    }

    /// Encodes a SegWit address. Version 0 uses bech32, later versions bech32m.
    static func encodeSegwit(hrp: String, version: UInt8, program: [UInt8]) -> String? {
        guard var data = convertBits(program, from: 8, to: 5, pad: true) else { return nil }
        data.insert(version, at: 0)
        let variant: Variant = version == 0 ? .bech32 : .bech32m
        let checksum = createChecksum(hrp: hrp, data: data, variant: variant)
        return hrp + "1" + String((data + checksum).map { charset[Int($0)] })
    }

    /// Returns the witness version and program of a valid SegWit address.
    static func decodeSegwit(_ address: String, hrp expectedHRP: String) -> (version: UInt8, program: [UInt8])? {
        let lower = address.lowercased()
        // Mixed case is not allowed by the spec.
        if address != lower && address != address.uppercased() { return nil }
        guard let separator = lower.lastIndex(of: "1"), separator > lower.startIndex else { return nil }
        let hrp = String(lower[lower.startIndex..<separator])
        guard hrp == expectedHRP else { return nil }

        let payload = lower[lower.index(after: separator)...]
        var values: [UInt8] = []
        for character in payload {
            guard let index = charset.firstIndex(of: character) else { return nil }
            values.append(UInt8(index))
        }
        guard values.count > 6, let version = values.first else { return nil }

        let variant: Variant = version == 0 ? .bech32 : .bech32m
        guard polymod(expand(hrp) + values) == variant.constant else { return nil }

        let program = Array(values.dropFirst().dropLast(6))
        guard let bytes = convertBits(program, from: 5, to: 8, pad: false) else { return nil }
        let validLength = version == 0 ? (bytes.count == 20 || bytes.count == 32) : (bytes.count >= 2 && bytes.count <= 40)
        guard version <= 16, validLength else { return nil }
        return (version, bytes)
    }

    // MARK: Internals

    private static func createChecksum(hrp: String, data: [UInt8], variant: Variant) -> [UInt8] {
        let values = expand(hrp) + data + [0, 0, 0, 0, 0, 0]
        let mod = polymod(values) ^ variant.constant
        return (0..<6).map { UInt8((mod >> (5 * (5 - UInt32($0)))) & 31) }
    }

    private static func expand(_ hrp: String) -> [UInt8] {
        let bytes = [UInt8](hrp.utf8)
        return bytes.map { $0 >> 5 } + [0] + bytes.map { $0 & 31 }
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var check: UInt32 = 1
        for value in values {
            let top = check >> 25
            check = (check & 0x1ff_ffff) << 5 ^ UInt32(value)
            for i in 0..<5 where (top >> UInt32(i)) & 1 == 1 {
                check ^= generator[i]
            }
        }
        return check
    }

    /// Regroups bits, e.g. 8-bit bytes into the 5-bit symbols bech32 uses.
    private static func convertBits(_ data: [UInt8], from: UInt32, to: UInt32, pad: Bool) -> [UInt8]? {
        var accumulator: UInt32 = 0
        var bits: UInt32 = 0
        var out: [UInt8] = []
        let maxValue: UInt32 = (1 << to) - 1
        for value in data {
            accumulator = (accumulator << from) | UInt32(value)
            bits += from
            while bits >= to {
                bits -= to
                out.append(UInt8((accumulator >> bits) & maxValue))
            }
        }
        if pad {
            if bits > 0 { out.append(UInt8((accumulator << (to - bits)) & maxValue)) }
        } else if bits >= from || ((accumulator << (to - bits)) & maxValue) != 0 {
            return nil
        }
        return out
    }
}
