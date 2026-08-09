import Foundation
import CryptoKit

enum SolanaError: LocalizedError {
    case rpc(String)
    case malformedResponse
    case invalidAddress
    case noTokenAccount(String)
    case noSenderTokenAccount

    var errorDescription: String? {
        switch self {
        case .rpc(let message): message
        case .malformedResponse: String.loc("The Solana network gave an unexpected answer.")
        case .invalidAddress: String.loc("Invalid Solana address.")
        case .noTokenAccount(let symbol):
            String.loc("The recipient has no \(symbol) account on Solana yet. Ask them to receive a little \(symbol) first, then try again.")
        case .noSenderTokenAccount:
            String.loc("You have no account for this coin on Solana.")
        }
    }
}

enum SolanaService {
    /// The System Program's id is 32 zero bytes.
    private static let systemProgram = [UInt8](repeating: 0, count: 32)
    private static let tokenProgram = Base58.decode("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA") ?? []
    private static let lamportsPerSOL = Decimal(1_000_000_000)

    // MARK: Reading

    static func solBalance(owner: String) async throws -> Decimal {
        let result = try await call("getBalance", [owner])
        guard let wrapper = result as? [String: Any],
              let lamports = wrapper["value"] as? NSNumber else { throw SolanaError.malformedResponse }
        return Decimal(lamports.uint64Value) / lamportsPerSOL
    }

    /// Balance of one SPL token. Returns zero when the owner holds no account
    /// for that mint, which is the normal case for an untouched wallet.
    static func tokenBalance(owner: String, mint: String) async throws -> Decimal {
        let result = try await call("getTokenAccountsByOwner", [
            owner,
            ["mint": mint],
            ["encoding": "jsonParsed"],
        ])
        guard let wrapper = result as? [String: Any],
              let accounts = wrapper["value"] as? [[String: Any]] else { throw SolanaError.malformedResponse }
        var total = Decimal.zero
        for entry in accounts {
            guard let account = entry["account"] as? [String: Any],
                  let data = account["data"] as? [String: Any],
                  let parsed = data["parsed"] as? [String: Any],
                  let info = parsed["info"] as? [String: Any],
                  let amount = info["tokenAmount"] as? [String: Any],
                  let raw = amount["amount"] as? String,
                  let value = Decimal(string: raw),
                  let decimals = (amount["decimals"] as? NSNumber)?.intValue else { continue }
            total += value / pow(10, decimals)
        }
        return total
    }

    // MARK: Sending

    /// Transfers SOL. Returns the transaction signature.
    static func sendSOL(from keypair: SolanaKey.Keypair, to recipient: String, amount: Decimal) async throws -> String {
        guard let destination = Base58.decode(recipient), destination.count == 32 else {
            throw SolanaError.invalidAddress
        }
        let lamports = NSDecimalNumber(decimal: amount * lamportsPerSOL).uint64Value
        let blockhash = try await latestBlockhash()

        // System Program transfer: instruction index 2, then the lamport amount.
        var data: [UInt8] = [2, 0, 0, 0]
        data.append(contentsOf: withUnsafeBytes(of: lamports.littleEndian) { Array($0) })

        let message = buildMessage(
            accounts: [keypair.publicKey, destination, systemProgram],
            readonlyUnsigned: 1,             // the system program
            blockhash: blockhash,
            programIndex: 2,
            accountIndices: [0, 1],
            data: data)
        return try await sign(message: message, with: keypair)
    }

    private static func sign(message: [UInt8], with keypair: SolanaKey.Keypair) async throws -> String {
        let signature = try keypair.privateKey.signature(for: Data(message))
        var transaction: [UInt8] = [1]           // one signature
        transaction += [UInt8](signature)
        transaction += message
        let encoded = Data(transaction).base64EncodedString()
        let result = try await call("sendTransaction", [encoded, ["encoding": "base64"]])
        guard let signatureString = result as? String else { throw SolanaError.malformedResponse }
        return signatureString
    }

    /// Address of the account holding `mint` for `owner`, straight from the
    /// network. Asking beats deriving it locally: a mistake in the derivation
    /// would send coins to an address nobody controls.
    private static func tokenAccount(owner: String, mint: String) async throws -> [UInt8]? {
        let result = try await call("getTokenAccountsByOwner", [
            owner, ["mint": mint], ["encoding": "jsonParsed"],
        ])
        guard let wrapper = result as? [String: Any],
              let accounts = wrapper["value"] as? [[String: Any]] else { throw SolanaError.malformedResponse }
        guard let pubkey = accounts.first?["pubkey"] as? String,
              let bytes = Base58.decode(pubkey), bytes.count == 32 else { return nil }
        return bytes
    }

    /// Transfers an SPL token such as USDC or USDT.
    static func sendToken(from keypair: SolanaKey.Keypair, to recipient: String, mint: String,
                          amount: Decimal, decimals: Int, symbol: String) async throws -> String {
        guard let mintKey = Base58.decode(mint), mintKey.count == 32,
              Base58.decode(recipient)?.count == 32 else { throw SolanaError.invalidAddress }
        guard let source = try await tokenAccount(owner: keypair.address, mint: mint) else {
            throw SolanaError.noSenderTokenAccount
        }
        guard let destination = try await tokenAccount(owner: recipient, mint: mint) else {
            throw SolanaError.noTokenAccount(symbol)
        }

        let raw = NSDecimalNumber(decimal: amount * pow(10, decimals)).uint64Value
        // Token Program "transferChecked": index 12, amount, then the decimals
        // the sender expects — the network rejects the transfer if they disagree.
        var data: [UInt8] = [12]
        data.append(contentsOf: withUnsafeBytes(of: raw.littleEndian) { Array($0) })
        data.append(UInt8(decimals))

        let blockhash = try await latestBlockhash()
        // Order matters: signer, then writable, then read-only.
        let accounts = [keypair.publicKey, source, destination, mintKey, tokenProgram]
        let message = buildMessage(
            accounts: accounts,
            readonlyUnsigned: 2,            // mint and the token program
            blockhash: blockhash,
            programIndex: 4,
            accountIndices: [1, 3, 2, 0],   // source, mint, destination, owner
            data: data)

        return try await sign(message: message, with: keypair)
    }

    /// True once the network reports the transaction as confirmed.
    static func isConfirmed(signature: String) async throws -> Bool {
        let result = try await call("getSignatureStatuses", [[signature]])
        guard let wrapper = result as? [String: Any],
              let statuses = wrapper["value"] as? [Any],
              let first = statuses.first as? [String: Any] else { return false }
        if first["err"] is [String: Any] { return false }
        let status = first["confirmationStatus"] as? String
        return status == "confirmed" || status == "finalized"
    }

    // MARK: Message building

    /// A single-instruction message. `accounts` must already be in Solana's
    /// required order: the signing payer, then writable accounts, then read-only.
    private static func buildMessage(accounts: [[UInt8]], readonlyUnsigned: UInt8, blockhash: [UInt8],
                                     programIndex: UInt8, accountIndices: [UInt8], data: [UInt8]) -> [UInt8] {
        var message: [UInt8] = [
            1,                  // signatures required
            0,                  // read-only signed accounts
            readonlyUnsigned,
        ]
        message += compactLength(accounts.count)
        for key in accounts { message += key }
        message += blockhash
        message += compactLength(1)             // one instruction
        message.append(programIndex)
        message += compactLength(accountIndices.count)
        message += accountIndices
        message += compactLength(data.count)
        message += data
        return message
    }

    /// Solana's compact-u16: 7 bits per byte, high bit marks "more to come".
    private static func compactLength(_ value: Int) -> [UInt8] {
        var remaining = value
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0x7f)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            out.append(byte)
        } while remaining != 0
        return out
    }

    private static func latestBlockhash() async throws -> [UInt8] {
        let result = try await call("getLatestBlockhash", [["commitment": "finalized"]])
        guard let wrapper = result as? [String: Any],
              let value = wrapper["value"] as? [String: Any],
              let hash = value["blockhash"] as? String,
              let bytes = Base58.decode(hash), bytes.count == 32 else {
            throw SolanaError.malformedResponse
        }
        return bytes
    }

    // MARK: Transport

    private static func call(_ method: String, _ params: [Any]) async throws -> Any {
        var request = URLRequest(url: Chain.solana.rpc)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": method, "params": params,
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SolanaError.malformedResponse
        }
        if let error = root["error"] as? [String: Any] {
            throw SolanaError.rpc(error["message"] as? String ?? "Solana RPC error")
        }
        guard let result = root["result"] else { throw SolanaError.malformedResponse }
        return result
    }
}
