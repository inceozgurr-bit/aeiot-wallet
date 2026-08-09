import Foundation
import CryptoKit
import Web3Core

/// Builds and signs a native SegWit (P2WPKH) spend, following BIP143.
enum BitcoinTransaction {
    /// Opt into replace-by-fee so a stuck transaction can be bumped later.
    private static let sequence: UInt32 = 0xFFFF_FFFD
    private static let sighashAll: UInt32 = 1

    static func build(inputs: [BitcoinService.UTXO],
                      outputs: [(value: UInt64, script: [UInt8])],
                      keypair: BitcoinKey.Keypair) throws -> String {
        let scriptCode = p2wpkhScriptCode(hash160: keypair.hash160)

        // BIP143 reuses these three digests across every input.
        let hashPrevouts = doubleSHA256(inputs.flatMap { outpoint($0) })
        let hashSequence = doubleSHA256(inputs.flatMap { _ in littleEndian(sequence) })
        let hashOutputs = doubleSHA256(outputs.flatMap { output in
            littleEndian(output.value) + varint(output.script.count) + output.script
        })

        var witnesses: [[UInt8]] = []
        for input in inputs {
            var preimage: [UInt8] = []
            preimage += littleEndian(UInt32(2))            // version
            preimage += hashPrevouts
            preimage += hashSequence
            preimage += outpoint(input)
            preimage += scriptCode
            preimage += littleEndian(input.value)
            preimage += littleEndian(sequence)
            preimage += hashOutputs
            preimage += littleEndian(UInt32(0))            // locktime
            preimage += littleEndian(sighashAll)

            let digest = doubleSHA256(preimage)
            let (serialized, _) = SECP256K1.signForRecovery(hash: Data(digest), privateKey: keypair.privateKey)
            guard let raw = serialized, raw.count >= 64 else {
                throw BitcoinError.api("Signing failed")
            }
            // Same DER + low-S rule as XRP; Bitcoin then appends the hash type.
            let der = XRPTransaction.derSignature(r: Array(raw[0..<32]), s: Array(raw[32..<64]))
            let signature = der + [UInt8(sighashAll)]
            let publicKey = [UInt8](keypair.publicKey)
            witnesses.append(varint(2) + varint(signature.count) + signature
                             + varint(publicKey.count) + publicKey)
        }

        var tx: [UInt8] = []
        tx += littleEndian(UInt32(2))                      // version
        tx += [0x00, 0x01]                                 // SegWit marker and flag
        tx += varint(inputs.count)
        for input in inputs {
            tx += outpoint(input)
            tx += [0x00]                                   // empty scriptSig for SegWit
            tx += littleEndian(sequence)
        }
        tx += varint(outputs.count)
        for output in outputs {
            tx += littleEndian(output.value)
            tx += varint(output.script.count)
            tx += output.script
        }
        for witness in witnesses { tx += witness }
        tx += littleEndian(UInt32(0))                      // locktime

        return tx.map { String(format: "%02x", $0) }.joined()
    }

    /// The 36-byte reference to the coin being spent. Bitcoin writes txids
    /// reversed on the wire, which is easy to miss and invalidates everything.
    private static func outpoint(_ utxo: BitcoinService.UTXO) -> [UInt8] {
        var txid = hexBytes(utxo.txid)
        txid.reverse()
        return txid + littleEndian(utxo.vout)
    }

    /// P2WPKH signs against the equivalent P2PKH script, length-prefixed.
    private static func p2wpkhScriptCode(hash160: [UInt8]) -> [UInt8] {
        [0x19, 0x76, 0xa9, 0x14] + hash160 + [0x88, 0xac]
    }

    private static func doubleSHA256(_ bytes: [UInt8]) -> [UInt8] {
        let once = SHA256.hash(data: Data(bytes))
        return [UInt8](SHA256.hash(data: Data(once)))
    }

    private static func varint(_ value: Int) -> [UInt8] {
        switch value {
        case ..<0xfd: [UInt8(value)]
        case ..<0x1_0000: [0xfd] + littleEndian(UInt16(value))
        default: [0xfe] + littleEndian(UInt32(value))
        }
    }

    private static func littleEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    private static func hexBytes(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex, let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
            out.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        return out
    }
}
