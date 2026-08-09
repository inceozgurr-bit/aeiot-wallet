import Foundation
import Web3Core

enum XRPService {
    private static let dropsPerXRP = Decimal(1_000_000)

    /// Balance of an XRP account. An account that has never been funded does
    /// not exist on the ledger yet, which the network reports as an error —
    /// that means zero, not a failure.
    static func balance(account: String) async throws -> Decimal {
        let result = try await call("account_info", [
            ["account": account, "ledger_index": "validated"],
        ])
        if let error = result["error"] as? String {
            if error == "actNotFound" { return 0 }
            throw SolanaError.rpc(error)
        }
        guard let data = result["account_data"] as? [String: Any],
              let drops = data["Balance"] as? String,
              let value = Decimal(string: drops) else {
            throw SolanaError.malformedResponse
        }
        return value / dropsPerXRP
    }

    /// XRP keeps a small amount locked as an account reserve, so a brand-new
    /// account must be funded with at least this much before it exists at all.
    static func accountReserve() async -> Decimal? {
        guard let result = try? await call("server_info", [[:]]),
              let info = result["info"] as? [String: Any],
              let ledger = info["validated_ledger"] as? [String: Any],
              let reserve = ledger["reserve_base_xrp"] as? NSNumber else { return nil }
        return Decimal(reserve.doubleValue)
    }

    /// Sends XRP. Returns the transaction hash.
    static func send(from keypair: XRPKey.Keypair, to destination: String, amount: Decimal) async throws -> String {
        guard XRPKey.isValidAddress(destination) else { throw SolanaError.invalidAddress }
        let account = keypair.address

        let info = try await call("account_info", [["account": account, "ledger_index": "current"]])
        guard let data = info["account_data"] as? [String: Any],
              let sequence = (data["Sequence"] as? NSNumber)?.uint32Value else {
            // No Sequence means the account was never funded.
            throw SolanaError.rpc(String.loc("This XRP account is not activated yet."))
        }
        let current = try await call("ledger_current", [[:]])
        guard let ledgerIndex = (current["ledger_current_index"] as? NSNumber)?.uint32Value else {
            throw SolanaError.malformedResponse
        }

        let payment = XRPTransaction.Payment(
            account: account,
            destination: destination,
            drops: NSDecimalNumber(decimal: amount * dropsPerXRP).uint64Value,
            fee: 12,                                   // standard minimum fee in drops
            sequence: sequence,
            // Expire the transaction instead of letting it hang around.
            lastLedgerSequence: ledgerIndex + 20,
            publicKey: [UInt8](keypair.publicKey))

        guard let signingData = XRPTransaction.signingData(payment) else {
            throw SolanaError.invalidAddress
        }
        let digest = XRPTransaction.hashToSign(signingData)
        let (serialized, _) = SECP256K1.signForRecovery(hash: Data(digest), privateKey: keypair.privateKey)
        guard let raw = serialized, raw.count >= 64 else { throw SolanaError.malformedResponse }
        let signature = XRPTransaction.derSignature(
            r: Array(raw[0..<32]), s: Array(raw[32..<64]))

        guard let blob = XRPTransaction.signedBlob(payment, signature: signature) else {
            throw SolanaError.malformedResponse
        }
        let result = try await call("submit", [["tx_blob": blob]])
        guard let engineResult = result["engine_result"] as? String else {
            throw SolanaError.malformedResponse
        }
        // tesSUCCESS means applied; ter/tec codes are queued or failed.
        guard engineResult == "tesSUCCESS" else {
            throw SolanaError.rpc(result["engine_result_message"] as? String ?? engineResult)
        }
        guard let tx = result["tx_json"] as? [String: Any],
              let hash = tx["hash"] as? String else { throw SolanaError.malformedResponse }
        return hash
    }

    /// True once the transaction is in a validated ledger.
    static func isConfirmed(hash: String) async throws -> Bool {
        let result = try await call("tx", [["transaction": hash]])
        return (result["validated"] as? Bool) == true
    }

    private static func call(_ method: String, _ params: [[String: Any]]) async throws -> [String: Any] {
        var request = URLRequest(url: Chain.xrp.rpc)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "method": method, "params": params,
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any] else {
            throw SolanaError.malformedResponse
        }
        return result
    }
}
