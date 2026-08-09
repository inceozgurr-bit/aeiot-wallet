import Foundation
import CryptoKit
import BigInt

/// Just enough of the XRPL binary codec to build and sign a Payment.
/// Fields must appear in ascending (type, field) order — the ledger rejects
/// anything else, so the order below is deliberate.
enum XRPTransaction {
    /// Prefix that marks the bytes as "single signature input".
    private static let signingPrefix: [UInt8] = [0x53, 0x54, 0x58, 0x00]
    private static let curveOrder = BigUInt(
        "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141", radix: 16)!

    struct Payment {
        let account: String
        let destination: String
        let drops: UInt64
        let fee: UInt64
        let sequence: UInt32
        let lastLedgerSequence: UInt32
        let publicKey: [UInt8]
    }

    /// The bytes to sign: the transaction without its signature, prefixed.
    static func signingData(_ payment: Payment) -> [UInt8]? {
        guard let body = serialize(payment, signature: nil) else { return nil }
        return signingPrefix + body
    }

    /// Hex blob ready for the `submit` command.
    static func signedBlob(_ payment: Payment, signature: [UInt8]) -> String? {
        guard let body = serialize(payment, signature: signature) else { return nil }
        return body.map { String(format: "%02X", $0) }.joined()
    }

    static func hashToSign(_ bytes: [UInt8]) -> [UInt8] {
        Array([UInt8](SHA512.hash(data: Data(bytes))).prefix(32))
    }

    /// Turns a raw (r, s) pair into the DER encoding XRPL expects, with the
    /// low-S form the network requires.
    static func derSignature(r: [UInt8], s: [UInt8]) -> [UInt8] {
        var sValue = BigUInt(Data(s))
        if sValue > curveOrder / 2 { sValue = curveOrder - sValue }
        var sBytes = [UInt8](sValue.serialize())
        while sBytes.count < 32 { sBytes.insert(0, at: 0) }

        func encode(_ value: [UInt8]) -> [UInt8] {
            var trimmed = Array(value.drop { $0 == 0 })
            if trimmed.isEmpty { trimmed = [0] }
            if trimmed[0] & 0x80 != 0 { trimmed.insert(0, at: 0) }   // keep it positive
            return [0x02, UInt8(trimmed.count)] + trimmed
        }
        let parts = encode(r) + encode(sBytes)
        return [0x30, UInt8(parts.count)] + parts
    }

    // MARK: Serialization

    private static func serialize(_ payment: Payment, signature: [UInt8]?) -> [UInt8]? {
        guard let account = accountID(payment.account),
              let destination = accountID(payment.destination) else { return nil }

        var out: [UInt8] = []
        out += fieldID(type: 1, field: 2) + [0x00, 0x00]                    // TransactionType: Payment
        out += fieldID(type: 2, field: 2) + bigEndian(0x8000_0000)          // Flags: fully canonical sig
        out += fieldID(type: 2, field: 4) + bigEndian(payment.sequence)
        out += fieldID(type: 2, field: 27) + bigEndian(payment.lastLedgerSequence)
        out += fieldID(type: 6, field: 1) + amount(payment.drops)           // Amount
        out += fieldID(type: 6, field: 8) + amount(payment.fee)             // Fee
        out += fieldID(type: 7, field: 3) + variableLength(payment.publicKey)
        if let signature {
            out += fieldID(type: 7, field: 4) + variableLength(signature)
        }
        out += fieldID(type: 8, field: 1) + variableLength(account)
        out += fieldID(type: 8, field: 3) + variableLength(destination)
        return out
    }

    private static func fieldID(type: UInt8, field: UInt8) -> [UInt8] {
        if type < 16 && field < 16 { return [type << 4 | field] }
        if type < 16 { return [type << 4, field] }
        if field < 16 { return [field, type] }
        return [0, type, field]
    }

    /// XRP amounts are 8 bytes with the top "not an IOU" bit set.
    private static func amount(_ drops: UInt64) -> [UInt8] {
        let value = drops | 0x4000_0000_0000_0000
        return withUnsafeBytes(of: value.bigEndian) { Array($0) }
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian) { Array($0) }
    }

    /// Length-prefixed blob. Our fields are always under 193 bytes.
    private static func variableLength(_ bytes: [UInt8]) -> [UInt8] {
        [UInt8(bytes.count)] + bytes
    }

    /// The 20-byte account id inside an r… address.
    private static func accountID(_ address: String) -> [UInt8]? {
        guard XRPKey.isValidAddress(address),
              let decoded = Base58.decode(address, alphabet: Base58.ripple) else { return nil }
        return Array(decoded[1..<21])
    }
}
