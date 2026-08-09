import Foundation
import CryptoKit
import Web3Core

enum BitcoinError: LocalizedError {
    case api(String)
    case notEnoughFunds
    case invalidAddress
    case dustAmount

    var errorDescription: String? {
        switch self {
        case .api(let message): message
        case .notEnoughFunds: String.loc("Not enough Bitcoin to cover the amount plus the network fee.")
        case .invalidAddress: String.loc("Invalid Bitcoin address. It should start with bc1.")
        case .dustAmount: String.loc("Amount is too small to send on Bitcoin.")
        }
    }
}

enum BitcoinService {
    private static let api = "https://blockstream.info/api"
    private static let satsPerBTC = Decimal(100_000_000)
    /// Outputs below this are rejected by the network as dust.
    private static let dustLimit: UInt64 = 546

    struct UTXO {
        let txid: String
        let vout: UInt32
        let value: UInt64
    }

    // MARK: Reading

    static func balance(address: String) async throws -> Decimal {
        let stats: [String: Any] = try await get("/address/\(address)")
        guard let chain = stats["chain_stats"] as? [String: Any],
              let funded = (chain["funded_txo_sum"] as? NSNumber)?.uint64Value,
              let spent = (chain["spent_txo_sum"] as? NSNumber)?.uint64Value else {
            throw BitcoinError.api("Unexpected response")
        }
        return Decimal(funded - spent) / satsPerBTC
    }

    /// Total across a wallet's addresses. Bitcoin spreads funds over many
    /// addresses, so a single-address balance would understate the wallet.
    /// Queried in parallel; an address that fails contributes zero.
    static func balance(addresses: [String]) async -> Decimal {
        await withTaskGroup(of: Decimal.self) { group in
            for address in addresses {
                group.addTask { (try? await balance(address: address)) ?? 0 }
            }
            var total = Decimal.zero
            for await amount in group { total += amount }
            return total
        }
    }

    /// Spendable coins across every address, each paired with the key that can
    /// sign it — inputs from different addresses need different signatures.
    static func spendableCoins(for keypairs: [BitcoinKey.Keypair]) async -> [(utxo: UTXO, key: BitcoinKey.Keypair)] {
        await withTaskGroup(of: [(UTXO, BitcoinKey.Keypair)].self) { group in
            for key in keypairs {
                group.addTask {
                    let found = (try? await utxos(address: key.address)) ?? []
                    return found.map { ($0, key) }
                }
            }
            var all: [(UTXO, BitcoinKey.Keypair)] = []
            for await chunk in group { all += chunk }
            return all.map { (utxo: $0.0, key: $0.1) }
        }
    }

    static func utxos(address: String) async throws -> [UTXO] {
        let list: [[String: Any]] = try await get("/address/\(address)/utxo")
        return list.compactMap { entry in
            guard let txid = entry["txid"] as? String,
                  let vout = (entry["vout"] as? NSNumber)?.uint32Value,
                  let value = (entry["value"] as? NSNumber)?.uint64Value else { return nil }
            return UTXO(txid: txid, vout: vout, value: value)
        }
    }

    /// Satoshis per virtual byte for roughly half-hour confirmation.
    static func feeRate() async -> Double {
        guard let estimates: [String: Any] = try? await get("/fee-estimates"),
              let rate = (estimates["3"] ?? estimates["6"]) as? NSNumber else { return 8 }
        return max(1, rate.doubleValue)
    }

    // MARK: Sending

    static func send(from keypair: BitcoinKey.Keypair, change changeKeypair: BitcoinKey.Keypair,
                     to recipient: String, amount: Decimal) async throws -> String {
        guard let outputScript = BitcoinKey.outputScript(for: recipient) else {
            throw BitcoinError.invalidAddress
        }
        let target = NSDecimalNumber(decimal: amount * satsPerBTC).uint64Value
        guard target >= dustLimit else { throw BitcoinError.dustAmount }

        let available = try await utxos(address: keypair.address).sorted { $0.value > $1.value }
        let rate = await feeRate()

        // Pick inputs largest-first until the amount plus its own fee is covered.
        var chosen: [UTXO] = []
        var total: UInt64 = 0
        var fee: UInt64 = 0
        for utxo in available {
            chosen.append(utxo)
            total += utxo.value
            // P2WPKH sizes: 10 base + 68 per input + 31 per output (two outputs).
            let vsize = 10 + 68 * chosen.count + 31 * 2
            fee = UInt64((Double(vsize) * rate).rounded(.up))
            if total >= target + fee { break }
        }
        guard !chosen.isEmpty, total >= target + fee else { throw BitcoinError.notEnoughFunds }

        var outputs: [(value: UInt64, script: [UInt8])] = [(target, outputScript)]
        let change = total - target - fee
        // Change under the dust limit goes to the miners instead of creating an
        // output nobody can ever spend.
        if change >= dustLimit {
            guard let changeScript = BitcoinKey.outputScript(for: changeKeypair.address) else {
                throw BitcoinError.invalidAddress
            }
            outputs.append((change, changeScript))
        }

        let raw = try BitcoinTransaction.build(inputs: chosen, outputs: outputs, keypair: keypair)
        return try await postTransaction(hex: raw)
    }

    static func isConfirmed(txid: String) async -> Bool {
        guard let status: [String: Any] = try? await get("/tx/\(txid)/status") else { return false }
        return (status["confirmed"] as? Bool) == true
    }

    // MARK: Transport

    private static func postTransaction(hex: String) async throws -> String {
        guard let url = URL(string: api + "/tx") else { throw BitcoinError.api("Bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(hex.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let body = String(data: data, encoding: .utf8) ?? ""
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BitcoinError.api(body.isEmpty ? "Broadcast failed" : body)
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func get<T>(_ path: String) async throws -> T {
        guard let url = URL(string: api + path) else { throw BitcoinError.api("Bad URL") }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let value = try JSONSerialization.jsonObject(with: data) as? T else {
            throw BitcoinError.api("Unexpected response")
        }
        return value
    }
}
