import Foundation

struct Activity: Identifiable, Hashable {
    let chain: Chain
    let hash: String
    let symbol: String
    let amount: Decimal
    let isIncoming: Bool
    let date: Date
    var id: String { "\(chain.id).\(hash).\(symbol)" }
}

enum HistoryService {
    /// Recent token transfers across every network that has a public Blockscout
    /// instance, newest first. Networks are queried in parallel; one failing
    /// network just contributes nothing.
    static func recentTransfers(for address: String) async -> [Activity] {
        await recentTransfers(evm: address, bitcoin: [], solana: nil, xrp: nil)
    }

    /// History across every network the wallet holds, newest first. Each network
    /// is queried in parallel and one that fails simply contributes nothing.
    static func recentTransfers(evm: String?, bitcoin: [String],
                                solana: String?, xrp: String?) async -> [Activity] {
        let merged = await withTaskGroup(of: [Activity].self) { group in
            if let evm {
                for chain in Chain.all where chain.blockscout != nil {
                    group.addTask { await transfers(for: evm, on: chain) }
                }
            }
            if !bitcoin.isEmpty {
                group.addTask { await bitcoinTransfers(addresses: bitcoin) }
            }
            if let solana {
                group.addTask { await solanaTransfers(owner: solana) }
            }
            if let xrp {
                group.addTask { await xrpTransfers(account: xrp) }
            }
            var all: [Activity] = []
            for await chunk in group { all += chunk }
            return all
        }
        return merged.sorted { $0.date > $1.date }
    }

    /// Bitcoin history. Blockstream returns full transactions, so the net effect
    /// on the wallet is inputs we own subtracted from outputs we own.
    static func bitcoinTransfers(addresses: [String]) async -> [Activity] {
        guard !addresses.isEmpty else { return [] }
        let owned = Set(addresses)
        // Querying all forty addresses would be wasteful; the first few of each
        // branch hold the activity of any normally-used wallet.
        let scanned = Array(addresses.prefix(4)) + Array(addresses.dropFirst(20).prefix(2))
        let items = await withTaskGroup(of: [[String: Any]].self) { group in
            for address in scanned {
                group.addTask {
                    guard let url = URL(string: "https://blockstream.info/api/address/\(address)/txs"),
                          let (data, _) = try? await URLSession.shared.data(from: url),
                          let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                    else { return [] }
                    return rows
                }
            }
            var all: [[String: Any]] = []
            for await chunk in group { all += chunk }
            return all
        }
        // The same transaction can appear under several of our addresses.
        var seen = Set<String>()
        let unique = items.filter { item in
            guard let txid = item["txid"] as? String else { return false }
            return seen.insert(txid).inserted
        }

        return unique.prefix(25).compactMap { item -> Activity? in
            guard let txid = item["txid"] as? String else { return nil }
            let outs = (item["vout"] as? [[String: Any]]) ?? []
            let ins = (item["vin"] as? [[String: Any]]) ?? []
            let received = outs.reduce(Int64(0)) { sum, out in
                guard let address = out["scriptpubkey_address"] as? String, owned.contains(address),
                      let value = (out["value"] as? NSNumber)?.int64Value else { return sum }
                return sum + value
            }
            let spent = ins.reduce(Int64(0)) { sum, input in
                guard let prev = input["prevout"] as? [String: Any],
                      let address = prev["scriptpubkey_address"] as? String, owned.contains(address),
                      let value = (prev["value"] as? NSNumber)?.int64Value else { return sum }
                return sum + value
            }
            let net = received - spent
            guard net != 0 else { return nil }
            let time = ((item["status"] as? [String: Any])?["block_time"] as? NSNumber)?.doubleValue
            return Activity(
                chain: .bitcoin, hash: txid, symbol: "BTC",
                amount: Decimal(abs(net)) / 100_000_000,
                isIncoming: net > 0,
                date: time.map { Date(timeIntervalSince1970: $0) } ?? .now)
        }
    }

    /// XRP history. `account_tx` returns the transactions themselves, so the
    /// amount is read directly — only plain XRP Payments are listed.
    static func xrpTransfers(account: String) async -> [Activity] {
        var request = URLRequest(url: Chain.xrp.rpc)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "method": "account_tx",
            "params": [["account": account, "limit": 25, "ledger_index_min": -1]],
        ])
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let rows = result["transactions"] as? [[String: Any]] else { return [] }

        return rows.compactMap { row -> Activity? in
            guard let tx = row["tx"] as? [String: Any],
                  tx["TransactionType"] as? String == "Payment",
                  let hash = tx["hash"] as? String,
                  // A dictionary here would mean an issued token, not plain XRP.
                  let drops = tx["Amount"] as? String,
                  let value = Decimal(string: drops) else { return nil }
            // XRP timestamps count from 2000-01-01, not 1970.
            let seconds = (tx["date"] as? NSNumber)?.doubleValue ?? 0
            return Activity(
                chain: .xrp, hash: hash, symbol: "XRP",
                amount: value / 1_000_000,
                isIncoming: (tx["Destination"] as? String) == account,
                date: Date(timeIntervalSince1970: seconds + 946_684_800))
        }
    }

    /// Solana history. Signatures come first, then each one is fetched to read
    /// how the account's balance actually moved.
    static func solanaTransfers(owner: String) async -> [Activity] {
        guard let signatures = await solanaSignatures(owner: owner) else { return [] }
        return await withTaskGroup(of: Activity?.self) { group in
            for signature in signatures.prefix(15) {
                group.addTask { await solanaActivity(signature: signature, owner: owner) }
            }
            var all: [Activity] = []
            for await item in group { if let item { all.append(item) } }
            return all
        }
    }

    private static func solanaSignatures(owner: String) async -> [(String, Double)]? {
        guard let result = await solanaCall("getSignaturesForAddress",
                                           [owner, ["limit": 15]]) as? [[String: Any]] else { return nil }
        return result.compactMap { row in
            guard row["err"] == nil, let signature = row["signature"] as? String else { return nil }
            return (signature, (row["blockTime"] as? NSNumber)?.doubleValue ?? 0)
        }
    }

    private static func solanaActivity(signature: (String, Double), owner: String) async -> Activity? {
        guard let result = await solanaCall("getTransaction", [
            signature.0, ["encoding": "jsonParsed", "maxSupportedTransactionVersion": 0],
        ]) as? [String: Any],
              let meta = result["meta"] as? [String: Any],
              let pre = meta["preBalances"] as? [NSNumber],
              let post = meta["postBalances"] as? [NSNumber],
              let message = (result["transaction"] as? [String: Any])?["message"] as? [String: Any],
              let keys = message["accountKeys"] as? [[String: Any]],
              let index = keys.firstIndex(where: { ($0["pubkey"] as? String) == owner }),
              index < pre.count, index < post.count else { return nil }

        let delta = post[index].int64Value - pre[index].int64Value
        guard delta != 0 else { return nil }
        return Activity(
            chain: .solana, hash: signature.0, symbol: "SOL",
            amount: Decimal(abs(delta)) / 1_000_000_000,
            isIncoming: delta > 0,
            date: Date(timeIntervalSince1970: signature.1))
    }

    private static func solanaCall(_ method: String, _ params: [Any]) async -> Any? {
        var request = URLRequest(url: Chain.solana.rpc)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": method, "params": params,
        ])
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root["result"]
    }

    private static func transfers(for address: String, on chain: Chain) async -> [Activity] {
        guard let host = chain.blockscout,
              let url = URL(string: "\(host)/api/v2/addresses/\(address)/token-transfers?type=ERC-20"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONDecoder().decode(TransfersResponse.self, from: data) else {
            return []
        }
        let owner = address.lowercased()
        let formatter = ISO8601DateFormatter()
        return root.items.prefix(25).compactMap { item -> Activity? in
            guard let decimalsString = item.token.decimals, let decimals = Int(decimalsString),
                  let rawValue = item.total.value, let raw = Decimal(string: rawValue) else { return nil }
            let amount = raw / pow(10, decimals)
            let date = formatter.date(from: item.timestamp) ?? .now
            return Activity(
                chain: chain,
                hash: item.transaction_hash,
                symbol: item.token.symbol ?? "?",
                amount: amount,
                isIncoming: item.to.hash.lowercased() == owner,
                date: date
            )
        }
    }

    private struct TransfersResponse: Decodable { let items: [Transfer] }
    private struct Transfer: Decodable {
        let transaction_hash: String
        let timestamp: String
        let to: Party
        let total: Total
        let token: TokenInfo
    }
    private struct Party: Decodable { let hash: String }
    private struct Total: Decodable { let value: String? }
    private struct TokenInfo: Decodable { let symbol: String?; let decimals: String? }
}
