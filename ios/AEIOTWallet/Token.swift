import Foundation

struct Token: Identifiable, Hashable {
    let chain: Chain
    let symbol: String
    let name: String
    let contract: String?   // nil = the chain's native coin
    let decimals: Int
    let coingeckoID: String?
    let logo: String
    /// Symbols repeat across chains, so the chain has to be part of the identity.
    var id: String { "\(chain.id).\(symbol)" }

    /// Key used to look up the USD price. AEIOT has no CoinGecko id, so it uses
    /// its own key which is filled from the Uniswap pool.
    var priceKey: String { coingeckoID ?? symbol.lowercased() }

    static let aeiot = Token(
        chain: .base, symbol: "AEIOT", name: "AEIOT",
        contract: "0x173ed85989D27e5AE3B05A0dC95E6C9862303Fab",
        decimals: 18, coingeckoID: nil, logo: "AEIOTLogo"
    )

    private static let baseTokens: [Token] = [
        aeiot,
        Token(chain: .base, symbol: "ETH", name: "Ethereum", contract: nil,
              decimals: 18, coingeckoID: "ethereum", logo: "logo_eth"),
        Token(chain: .base, symbol: "USDC", name: "USD Coin",
              contract: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
              decimals: 6, coingeckoID: "usd-coin", logo: "logo_usdc"),
        Token(chain: .base, symbol: "USDT", name: "Tether USD",
              contract: "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2",
              decimals: 6, coingeckoID: "tether", logo: "logo_usdt"),
        Token(chain: .base, symbol: "cbBTC", name: "Coinbase Wrapped BTC",
              contract: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf",
              decimals: 8, coingeckoID: "coinbase-wrapped-btc", logo: "logo_cbbtc"),
    ]

    private static let ethereumTokens: [Token] = [
        Token(chain: .ethereum, symbol: "ETH", name: "Ethereum", contract: nil,
              decimals: 18, coingeckoID: "ethereum", logo: "logo_eth"),
        Token(chain: .ethereum, symbol: "USDC", name: "USD Coin",
              contract: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
              decimals: 6, coingeckoID: "usd-coin", logo: "logo_usdc"),
        Token(chain: .ethereum, symbol: "USDT", name: "Tether USD",
              contract: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
              decimals: 6, coingeckoID: "tether", logo: "logo_usdt"),
        Token(chain: .ethereum, symbol: "WBTC", name: "Wrapped Bitcoin",
              contract: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
              decimals: 8, coingeckoID: "wrapped-bitcoin", logo: "logo_wbtc"),
    ]

    private static let arbitrumTokens: [Token] = [
        Token(chain: .arbitrum, symbol: "ETH", name: "Ethereum", contract: nil,
              decimals: 18, coingeckoID: "ethereum", logo: "logo_eth"),
        Token(chain: .arbitrum, symbol: "USDC", name: "USD Coin",
              contract: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
              decimals: 6, coingeckoID: "usd-coin", logo: "logo_usdc"),
        Token(chain: .arbitrum, symbol: "USDT", name: "Tether USD",
              contract: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",
              decimals: 6, coingeckoID: "tether", logo: "logo_usdt"),
        Token(chain: .arbitrum, symbol: "WBTC", name: "Wrapped Bitcoin",
              contract: "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f",
              decimals: 8, coingeckoID: "wrapped-bitcoin", logo: "logo_wbtc"),
    ]

    private static let optimismTokens: [Token] = [
        Token(chain: .optimism, symbol: "ETH", name: "Ethereum", contract: nil,
              decimals: 18, coingeckoID: "ethereum", logo: "logo_eth"),
        Token(chain: .optimism, symbol: "USDC", name: "USD Coin",
              contract: "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85",
              decimals: 6, coingeckoID: "usd-coin", logo: "logo_usdc"),
        Token(chain: .optimism, symbol: "USDT", name: "Tether USD",
              contract: "0x94b008aA00579c1307B0EF2c499aD98a8ce58e58",
              decimals: 6, coingeckoID: "tether", logo: "logo_usdt"),
    ]

    private static let polygonTokens: [Token] = [
        Token(chain: .polygon, symbol: "POL", name: "Polygon", contract: nil,
              decimals: 18, coingeckoID: "polygon-ecosystem-token", logo: "logo_pol"),
        Token(chain: .polygon, symbol: "USDC", name: "USD Coin",
              contract: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
              decimals: 6, coingeckoID: "usd-coin", logo: "logo_usdc"),
        Token(chain: .polygon, symbol: "USDT", name: "Tether USD",
              contract: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F",
              decimals: 6, coingeckoID: "tether", logo: "logo_usdt"),
    ]

    // BNB Chain issues its stablecoins with 18 decimals, not the usual 6.
    private static let bnbTokens: [Token] = [
        Token(chain: .bnb, symbol: "BNB", name: "BNB", contract: nil,
              decimals: 18, coingeckoID: "binancecoin", logo: "logo_bnb"),
        Token(chain: .bnb, symbol: "USDT", name: "Tether USD",
              contract: "0x55d398326f99059fF775485246999027B3197955",
              decimals: 18, coingeckoID: "tether", logo: "logo_usdt"),
        Token(chain: .bnb, symbol: "USDC", name: "USD Coin",
              contract: "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d",
              decimals: 18, coingeckoID: "usd-coin", logo: "logo_usdc"),
    ]

    // On Solana `contract` holds the SPL mint address instead of an 0x contract.
    private static let solanaTokens: [Token] = [
        Token(chain: .solana, symbol: "SOL", name: "Solana", contract: nil,
              decimals: 9, coingeckoID: "solana", logo: "logo_sol"),
        Token(chain: .solana, symbol: "USDC", name: "USD Coin",
              contract: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
              decimals: 6, coingeckoID: "usd-coin", logo: "logo_usdc"),
        Token(chain: .solana, symbol: "USDT", name: "Tether USD",
              contract: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",
              decimals: 6, coingeckoID: "tether", logo: "logo_usdt"),
    ]

    private static let xrpTokens: [Token] = [
        Token(chain: .xrp, symbol: "XRP", name: "XRP", contract: nil,
              decimals: 6, coingeckoID: "ripple", logo: "logo_xrp"),
    ]

    private static let bitcoinTokens: [Token] = [
        Token(chain: .bitcoin, symbol: "BTC", name: "Bitcoin", contract: nil,
              decimals: 8, coingeckoID: "bitcoin", logo: "logo_btc"),
    ]

    static let all: [Token] =
        baseTokens + ethereumTokens + arbitrumTokens + optimismTokens + polygonTokens
        + bnbTokens + solanaTokens + xrpTokens + bitcoinTokens

    /// Coins that can be swapped: those on networks with a verified router.
    /// Swaps stay inside one network — no bridging.
    static let swappable: [Token] = all.filter { $0.chain.canSwap }

    /// Networks offering swaps, in the order they appear in the picker.
    static let swappableChains: [Chain] = Chain.all.filter(\.canSwap)

    /// Display order: our own coin pinned to the top, then roughly by how
    /// widely held each coin is. Anything unlisted falls to the bottom.
    private static let displayOrder = [
        "AEIOT", "BTC", "ETH", "USDT", "USDC", "XRP", "SOL", "BNB", "cbBTC", "WBTC", "POL",
    ]

    /// One entry per coin, so ETH does not take four rows in the list.
    static let grouped: [TokenGroup] = {
        var order: [String] = []
        var buckets: [String: [Token]] = [:]
        for token in all {
            if buckets[token.symbol] == nil { order.append(token.symbol) }
            buckets[token.symbol, default: []].append(token)
        }
        return order
            .map { TokenGroup(symbol: $0, tokens: buckets[$0] ?? []) }
            .sorted {
                (displayOrder.firstIndex(of: $0.symbol) ?? .max)
                    < (displayOrder.firstIndex(of: $1.symbol) ?? .max)
            }
    }()
}

/// The same coin held across several networks, presented as a single row.
struct TokenGroup: Identifiable, Hashable {
    let symbol: String
    let tokens: [Token]
    var id: String { symbol }
    /// Stands in for the group wherever a single token is needed (logo, price).
    var primary: Token { tokens[0] }
    var name: String { primary.name }
}
