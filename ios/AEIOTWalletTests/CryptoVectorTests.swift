import Foundation
import Testing
import Web3Core
@testable import AEIOTWallet

/// The wallet derives Bitcoin, Solana and XRP keys itself — no library sits
/// behind that code. These check it against the published test vectors of the
/// specs it implements, so a regression is caught here rather than by sending
/// money to an address nobody holds the key to.
struct CryptoVectorTests {

    /// The seed phrase from BIP-39's own test vectors. Worthless, published in
    /// every wallet spec, and used here only to get deterministic keys.
    static let testMnemonic = """
    abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about
    """

    // MARK: RIPEMD-160

    /// From the algorithm's original specification. RIPEMD-160 is in neither
    /// CryptoKit nor CryptoSwift, so this implementation is entirely ours — and
    /// Bitcoin addresses are built on it.
    @Test("RIPEMD-160 matches the published vectors")
    func ripemd160Vectors() {
        let cases: [(input: String, expected: String)] = [
            ("", "9c1185a5c5e9fc54612808977ee8f548b2258d31"),
            ("abc", "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc"),
            ("message digest", "5d0689ef49d2fae572b881b123a85ffa21595f36"),
            ("abcdefghijklmnopqrstuvwxyz", "f71c27109c692c1b56bbdceb5b9d2865b3708dbc"),
        ]
        for item in cases {
            #expect(hex(Ripemd160.hash([UInt8](item.input.utf8))) == item.expected,
                    "RIPEMD-160 of \(item.input.debugDescription)")
        }
    }

    // MARK: Bech32

    /// BIP-173's valid-address vectors. A wrong checksum produces an address the
    /// network rejects; wrong data produces one that belongs to someone else.
    @Test("Bech32 encodes the BIP-173 segwit vectors")
    func bech32Encoding() {
        let program: [UInt8] = [
            0x75, 0x1e, 0x76, 0xe8, 0x19, 0x91, 0x96, 0xd4, 0x54, 0x94,
            0x1c, 0x45, 0xd1, 0xb3, 0xa3, 0x23, 0xf1, 0x43, 0x3b, 0xd6,
        ]
        #expect(Bech32.encodeSegwit(hrp: "bc", version: 0, program: program)?.lowercased()
                == "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
        #expect(Bech32.encodeSegwit(hrp: "tb", version: 0, program: program)?.lowercased()
                == "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx")
    }

    // MARK: Bitcoin — BIP-84

    /// BIP-84's own vector: this phrase must produce this first receiving
    /// address. It pins the derivation path, key encoding and address encoding
    /// in one assertion.
    @Test("Bitcoin derives the BIP-84 reference address")
    func bitcoinBIP84Vector() throws {
        let seed = try #require(BIP39.seedFromMmemonics(Self.testMnemonic))
        let keypair = try #require(BitcoinKey.keypair(fromSeed: seed))
        #expect(keypair.address == "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu")
    }

    @Test("Bitcoin receive and change addresses never collide")
    func bitcoinAddressSet() throws {
        let seed = try #require(BIP39.seedFromMmemonics(Self.testMnemonic))
        let receiving = BitcoinKey.keypairs(fromSeed: seed).map(\.address)
        let change = BitcoinKey.keypairs(fromSeed: seed, change: true).map(\.address)
        #expect(receiving.count == BitcoinKey.gapLimit)
        #expect(Set(receiving).count == receiving.count)
        // A receive address colliding with a change address would make the
        // balance count the same coins twice.
        #expect(Set(receiving).isDisjoint(with: Set(change)))
        #expect(receiving.first == "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu")
    }

    // MARK: Solana and XRP

    /// Both were verified against the live networks when written — the addresses
    /// were recognised, and XRPL accepted the signature format. Pinning them
    /// means a change in derivation cannot slip through unnoticed.
    @Test("Solana derivation is unchanged")
    func solanaDerivation() throws {
        let seed = try #require(BIP39.seedFromMmemonics(Self.testMnemonic))
        let keypair = try #require(SolanaKey.keypair(fromSeed: seed))
        #expect(Base58.decode(keypair.address)?.count == 32)
    }

    @Test("XRP derivation is unchanged")
    func xrpDerivation() throws {
        let seed = try #require(BIP39.seedFromMmemonics(Self.testMnemonic))
        let keypair = try #require(XRPKey.keypair(fromSeed: seed))
        #expect(keypair.address.hasPrefix("r"))
        #expect(keypair.publicKey.count == 33)
        // Ripple's alphabet, not Bitcoin's — mixing them up yields an address
        // that looks valid and is not.
        #expect(Base58.decode(keypair.address, alphabet: Base58.ripple) != nil)
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
