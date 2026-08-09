import Foundation
import CryptoKit
import Web3Core

/// Native SegWit (BIP84) keys — the bc1… addresses modern wallets use.
/// Same seed phrase as every other network, its own derivation path.
enum BitcoinKey {
    /// BIP84 account 0. Index 0 of the external chain is the receiving address;
    /// the internal chain (…/1/…) receives change when spending.
    private static let receivePath = "m/84'/0'/0'/0/0"
    private static let changePath = "m/84'/0'/0'/1/0"

    struct Keypair {
        let publicKey: Data      // 33-byte compressed
        let privateKey: Data

        /// HASH160 — the 20 bytes a bc1 address actually commits to.
        var hash160: [UInt8] {
            Ripemd160.hash([UInt8](SHA256.hash(data: publicKey)))
        }
        var address: String {
            Bech32.encodeSegwit(hrp: "bc", version: 0, program: hash160) ?? ""
        }
    }

    static func keypair(fromSeed seed: Data) -> Keypair? { derive(seed: seed, path: receivePath) }
    static func changeKeypair(fromSeed seed: Data) -> Keypair? { derive(seed: seed, path: changePath) }

    private static func derive(seed: Data, path: String) -> Keypair? {
        guard let node = HDNode(seed: seed)?.derive(path: path),
              let privateKey = node.privateKey else { return nil }
        return Keypair(publicKey: node.publicKey, privateKey: privateKey)
    }

    static func isValidAddress(_ address: String) -> Bool {
        Bech32.decodeSegwit(address, hrp: "bc") != nil
    }

    /// The locking script a payment to `address` must carry.
    static func outputScript(for address: String) -> [UInt8]? {
        guard let (version, program) = Bech32.decodeSegwit(address, hrp: "bc") else { return nil }
        let opcode: UInt8 = version == 0 ? 0x00 : (0x50 + version)   // OP_0 or OP_1..OP_16
        return [opcode, UInt8(program.count)] + program
    }
}
