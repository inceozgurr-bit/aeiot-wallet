import Foundation

/// RIPEMD-160, needed for XRP and Bitcoin addresses. Neither CryptoKit nor
/// CryptoSwift ships it, so it lives here. Verified against the RFC vectors.
enum Ripemd160 {
    private static let left: [Int] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
        3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
        1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
        4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13,
    ]
    private static let right: [Int] = [
        5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
        6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
        15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
        8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
        12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11,
    ]
    private static let shiftLeft: [UInt32] = [
        11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
        7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
        11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
        11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
        9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6,
    ]
    private static let shiftRight: [UInt32] = [
        8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
        9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
        9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
        15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
        8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11,
    ]
    private static let kLeft: [UInt32] = [0x0000_0000, 0x5a82_7999, 0x6ed9_eba1, 0x8f1b_bcdc, 0xa953_fd4e]
    private static let kRight: [UInt32] = [0x50a2_8be6, 0x5c4d_d124, 0x6d70_3ef3, 0x7a6d_76e9, 0x0000_0000]

    static func hash(_ message: [UInt8]) -> [UInt8] {
        var state: [UInt32] = [0x6745_2301, 0xefcd_ab89, 0x98ba_dcfe, 0x1032_5476, 0xc3d2_e1f0]

        // Pad to a multiple of 64 bytes: 0x80, zeros, then the bit length.
        var padded = message
        padded.append(0x80)
        while padded.count % 64 != 56 { padded.append(0) }
        let bitLength = UInt64(message.count) * 8
        padded.append(contentsOf: withUnsafeBytes(of: bitLength.littleEndian) { Array($0) })

        for blockStart in stride(from: 0, to: padded.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let base = blockStart + i * 4
                words[i] = UInt32(padded[base])
                    | UInt32(padded[base + 1]) << 8
                    | UInt32(padded[base + 2]) << 16
                    | UInt32(padded[base + 3]) << 24
            }

            var (al, bl, cl, dl, el) = (state[0], state[1], state[2], state[3], state[4])
            var (ar, br, cr, dr, er) = (state[0], state[1], state[2], state[3], state[4])

            for j in 0..<80 {
                let round = j / 16
                var temp = al &+ f(round, bl, cl, dl) &+ words[left[j]] &+ kLeft[round]
                temp = rotate(temp, shiftLeft[j]) &+ el
                (al, bl, cl, dl, el) = (el, temp, bl, rotate(cl, 10), dl)

                temp = ar &+ f(4 - round, br, cr, dr) &+ words[right[j]] &+ kRight[round]
                temp = rotate(temp, shiftRight[j]) &+ er
                (ar, br, cr, dr, er) = (er, temp, br, rotate(cr, 10), dr)
            }

            let carry = state[1] &+ cl &+ dr
            state[1] = state[2] &+ dl &+ er
            state[2] = state[3] &+ el &+ ar
            state[3] = state[4] &+ al &+ br
            state[4] = state[0] &+ bl &+ cr
            state[0] = carry
        }

        return state.flatMap { withUnsafeBytes(of: $0.littleEndian) { Array($0) } }
    }

    private static func f(_ round: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        switch round {
        case 0: x ^ y ^ z
        case 1: (x & y) | (~x & z)
        case 2: (x | ~y) ^ z
        case 3: (x & z) | (y & ~z)
        default: x ^ (y | ~z)
        }
    }

    private static func rotate(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value << count) | (value >> (32 - count))
    }
}
