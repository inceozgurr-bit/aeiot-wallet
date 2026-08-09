import Foundation
import BigInt

enum PriceService {
    /// USD prices keyed by CoinGecko id. Returns empty on any failure — prices are cosmetic.
    static func usdPrices(for tokens: [Token]) async -> [String: Double] {
        // The same coin appears on several networks; ask CoinGecko for it once.
        let ids = Set(tokens.compactMap(\.coingeckoID)).sorted().joined(separator: ",")
        guard !ids.isEmpty,
              let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(ids)&vs_currencies=usd"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode([String: [String: Double]].self, from: data) else {
            return [:]
        }
        return decoded.compactMapValues { $0["usd"] }
    }

    /// Price history for a coin over `days` (1, 7, 30, 365). Empty on failure.
    static func chart(for coingeckoID: String, days: Int) async -> [Double] {
        let urlString = "https://api.coingecko.com/api/v3/coins/\(coingeckoID)/market_chart?vs_currency=usd&days=\(days)"
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(ChartResponse.self, from: data) else {
            return []
        }
        return decoded.prices.map { $0[1] }
    }

    private struct ChartResponse: Decodable { let prices: [[Double]] }

    /// AEIOT price history from GeckoTerminal (its Uniswap pool's OHLCV).
    /// Returns close prices oldest→newest. Empty on failure.
    static func aeiotChart(days: Int) async -> [Double] {
        let pool = "0x7b1bECB73F87C13C73E4c653e6b42c5A90688422"
        let (timeframe, limit): (String, Int) = switch days {
        case 1: ("minute", 288)   // new pool: minute data has the most points early on
        case 7: ("hour", 168)
        case 30: ("day", 30)
        default: ("day", 365)
        }
        let urlString = "https://api.geckoterminal.com/api/v2/networks/base/pools/\(pool)/ohlcv/\(timeframe)?limit=\(limit)"
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = root["data"] as? [String: Any],
              let attrs = d["attributes"] as? [String: Any],
              let list = attrs["ohlcv_list"] as? [[Double]] else {
            return []
        }
        // GeckoTerminal returns newest→oldest; each row is [ts, o, h, l, c, v].
        return list.reversed().map { $0[4] }
    }

    /// AEIOT's live USD price read from its Uniswap v2 pool reserves.
    /// token0 = AEIOT, token1 = WETH (AEIOT address sorts lower). Returns nil on failure.
    static func aeiotUSDPrice(ethUSD: Double) async -> Double? {
        let pair = "0x7b1bECB73F87C13C73E4c653e6b42c5A90688422"
        // getReserves() selector 0x0902f1ac → returns (uint112 r0, uint112 r1, uint32 ts)
        let body: [String: Any] = [
            "jsonrpc": "2.0", "method": "eth_call", "id": 1,
            "params": [["to": pair, "data": "0x0902f1ac"], "latest"],
        ]
        guard let url = URL(string: "https://mainnet.base.org"),
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = payload
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hex = json["result"] as? String, hex.count >= 130 else { return nil }
        let clean = String(hex.dropFirst(2))
        guard let reserveAEIOT = BigUInt(clean.prefix(64), radix: 16),
              let reserveWETH = BigUInt(clean.dropFirst(64).prefix(64), radix: 16),
              reserveAEIOT > 0,
              let a = Double(reserveAEIOT.description), let w = Double(reserveWETH.description)
        else { return nil }
        let priceInEth = w / a // both 18 decimals, cancels out
        return priceInEth * ethUSD
    }
}
