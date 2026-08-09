import Foundation
import CryptoKit
import Web3Core

/// XRP uses the same curve as Ethereum (secp256k1) but writes addresses very
/// differently: RIPEMD160 over the key, base58 in Ripple's own alphabet.
enum XRPKey {
    /// The path Xumm/Xaman and Ledger use, so the same phrase opens this
    /// account in those wallets too.
    private static let path = "m/44'/144'/0'/0/0"

    struct Keypair {
        let publicKey: Data     // 33-byte compressed secp256k1 point
        let privateKey: Data
        var address: String { XRPKey.address(fromPublicKey: [UInt8](publicKey)) }
    }

    static func keypair(fromSeed seed: Data) -> Keypair? {
        guard let node = HDNode(seed: seed)?.derive(path: path),
              let privateKey = node.privateKey else { return nil }
        return Keypair(publicKey: node.publicKey, privateKey: privateKey)
    }

    static func address(fromPublicKey publicKey: [UInt8]) -> String {
        let accountID = Ripemd160.hash([UInt8](SHA256.hash(data: Data(publicKey))))
        return base58Check([0x00] + accountID)   // 0x00 marks an account address
    }

    static func isValidAddress(_ address: String) -> Bool {
        guard address.hasPrefix("r"),
              let bytes = Base58.decode(address, alphabet: Base58.ripple),
              bytes.count == 25, bytes[0] == 0x00 else { return false }
        let payload = Array(bytes.prefix(21))
        return checksum(payload) == Array(bytes.suffix(4))
    }

    private static func base58Check(_ payload: [UInt8]) -> String {
        Base58.encode(payload + checksum(payload), alphabet: Base58.ripple)
    }

    /// First four bytes of the double SHA256, as every base58check scheme does.
    private static func checksum(_ payload: [UInt8]) -> [UInt8] {
        let once = SHA256.hash(data: Data(payload))
        let twice = SHA256.hash(data: Data(once))
        return Array([UInt8](twice).prefix(4))
    }
}
