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
        let chains = Chain.all.filter { $0.blockscout != nil }
        let merged = await withTaskGroup(of: [Activity].self) { group in
            for chain in chains {
                group.addTask { await transfers(for: address, on: chain) }
            }
            var all: [Activity] = []
            for await chunk in group { all += chunk }
            return all
        }
        return merged.sorted { $0.date > $1.date }
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
