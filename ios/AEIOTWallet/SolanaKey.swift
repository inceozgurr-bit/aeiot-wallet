import Foundation
import CryptoKit

/// Base58. Solana and Bitcoin use the standard alphabet; XRP reorders it.
enum Base58 {
    static let bitcoin = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    static let ripple = Array("rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz")

    static func encode(_ bytes: [UInt8], alphabet: [Character] = bitcoin) -> String {
        var digits: [UInt8] = [0]
        for byte in bytes {
            var carry = Int(byte)
            for i in digits.indices {
                carry += Int(digits[i]) << 8
                digits[i] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }
        // Every leading zero byte becomes one leading "zero" character.
        let leadingZeros = bytes.prefix { $0 == 0 }.count
        return String(repeating: alphabet[0], count: leadingZeros)
            + String(digits.reversed().map { alphabet[Int($0)] })
    }

    static func decode(_ string: String, alphabet: [Character] = bitcoin) -> [UInt8]? {
        var bytes: [UInt8] = [0]
        for character in string {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            var carry = value
            for i in bytes.indices {
                carry += Int(bytes[i]) * 58
                bytes[i] = UInt8(carry & 0xff)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xff))
                carry >>= 8
            }
        }
        let leadingZeros = string.prefix { $0 == alphabet[0] }.count
        return [UInt8](repeating: 0, count: leadingZeros) + bytes.reversed()
    }
}

/// Solana keys come off the same seed phrase as the Ethereum ones, but on the
/// ed25519 curve via SLIP-0010 — so the address is completely different.
enum SolanaKey {
    /// The path Phantom, Solflare and the Solana CLI all use, so the same phrase
    /// opens this wallet in any of them.
    private static let path: [UInt32] = [44, 501, 0, 0]

    struct Keypair {
        let privateKey: Curve25519.Signing.PrivateKey
        var publicKey: [UInt8] { [UInt8](privateKey.publicKey.rawRepresentation) }
        var address: String { Base58.encode(publicKey) }
    }

    static func keypair(fromSeed seed: Data) -> Keypair? {
        var (key, chainCode) = master(seed: seed)
        for index in path {
            (key, chainCode) = derive(key: key, chainCode: chainCode, index: index)
        }
        guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: key) else {
            return nil
        }
        return Keypair(privateKey: privateKey)
    }

    private static func master(seed: Data) -> (Data, Data) {
        let mac = HMAC<SHA512>.authenticationCode(
            for: seed, using: SymmetricKey(data: Data("ed25519 seed".utf8)))
        let bytes = Data(mac)
        return (bytes.prefix(32), bytes.suffix(32))
    }

    /// ed25519 supports hardened derivation only, so every index gets 0x80000000.
    private static func derive(key: Data, chainCode: Data, index: UInt32) -> (Data, Data) {
        var payload = Data([0x00])
        payload.append(key)
        payload.append(contentsOf: withUnsafeBytes(of: (index | 0x8000_0000).bigEndian) { Array($0) })
        let mac = HMAC<SHA512>.authenticationCode(for: payload, using: SymmetricKey(data: chainCode))
        let bytes = Data(mac)
        return (bytes.prefix(32), bytes.suffix(32))
    }
}
