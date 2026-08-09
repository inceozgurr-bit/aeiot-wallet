import Foundation
import BigInt

/// What kind of network this is, which decides how keys, addresses and
/// transactions are handled.
enum ChainKind: Hashable, Sendable {
    /// Every EVM chain shares one 0x… address derived from the seed phrase.
    case evm(chainID: BigUInt)
    /// Solana derives a separate ed25519 address from the same seed phrase.
    case solana
    /// XRP uses the same curve as EVM but a different address format.
    case xrp
    /// Bitcoin: separate bc1… address and a completely different spend model.
    case bitcoin
}

/// A network the wallet talks to.
struct Chain: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: ChainKind
    /// Coin the network charges its fees in.
    let nativeSymbol: String
    let rpc: URL
    /// Block explorer base URL, used for the "view transaction" links.
    let explorer: String
    /// Blockscout instance for transfer history; nil where no public one exists.
    let blockscout: String?
    /// Uniswap-V2-compatible router, only where those pools hold real liquidity.
    /// Measured against spot: on Arbitrum the V2 pool quoted 7.8% under and
    /// SushiSwap's 25% under, so V2 is not used there — see `v3Router`.
    var swapRouter: String? = nil
    /// Uniswap V3, for the chains whose V2 pools are too thin to quote honestly.
    /// Measured on the pair V2 failed: within 0.06% of spot on Arbitrum, 0.25%
    /// on Optimism.
    var v3Router: String? = nil
    var v3Quoter: String? = nil
    /// Wrapped form of the native coin, which every pool pairs against.
    var wrappedNative: String? = nil

    var canSwap: Bool { swapRouter != nil || v3Router != nil }
    var usesV3: Bool { v3Router != nil }

    static let base = Chain(
        id: "base", name: "Base", kind: .evm(chainID: 8453), nativeSymbol: "ETH",
        rpc: URL(string: "https://mainnet.base.org")!,
        explorer: "https://basescan.org",
        blockscout: "https://base.blockscout.com",
        swapRouter: "0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24",
        wrappedNative: "0x4200000000000000000000000000000000000006")

    static let ethereum = Chain(
        id: "ethereum", name: "Ethereum", kind: .evm(chainID: 1), nativeSymbol: "ETH",
        rpc: URL(string: "https://ethereum-rpc.publicnode.com")!,
        explorer: "https://etherscan.io",
        blockscout: "https://eth.blockscout.com",
        swapRouter: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
        wrappedNative: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")

    static let arbitrum = Chain(
        id: "arbitrum", name: "Arbitrum", kind: .evm(chainID: 42161), nativeSymbol: "ETH",
        rpc: URL(string: "https://arb1.arbitrum.io/rpc")!,
        explorer: "https://arbiscan.io",
        blockscout: "https://arbitrum.blockscout.com",
        v3Router: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
        v3Quoter: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",
        wrappedNative: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1")

    static let optimism = Chain(
        id: "optimism", name: "Optimism", kind: .evm(chainID: 10), nativeSymbol: "ETH",
        rpc: URL(string: "https://mainnet.optimism.io")!,
        explorer: "https://optimistic.etherscan.io",
        // optimism.blockscout.com redirects here; skip the extra round trip.
        blockscout: "https://explorer.optimism.io",
        v3Router: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
        v3Quoter: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",
        wrappedNative: "0x4200000000000000000000000000000000000006")

    static let polygon = Chain(
        id: "polygon", name: "Polygon", kind: .evm(chainID: 137), nativeSymbol: "POL",
        // polygon-rpc.com now demands an API key; publicnode is open.
        rpc: URL(string: "https://polygon-bor-rpc.publicnode.com")!,
        explorer: "https://polygonscan.com",
        blockscout: "https://polygon.blockscout.com",
        swapRouter: "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff",
        wrappedNative: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270")

    static let bnb = Chain(
        id: "bnb", name: "BNB Chain", kind: .evm(chainID: 56), nativeSymbol: "BNB",
        rpc: URL(string: "https://bsc-dataseed.binance.org")!,
        explorer: "https://bscscan.com",
        blockscout: nil,
        swapRouter: "0x10ED43C718714eb63d5aA57B78B54704E256024E",
        wrappedNative: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c")

    static let solana = Chain(
        id: "solana", name: "Solana", kind: .solana, nativeSymbol: "SOL",
        rpc: URL(string: "https://api.mainnet-beta.solana.com")!,
        explorer: "https://solscan.io",
        blockscout: nil)

    static let xrp = Chain(
        id: "xrp", name: "XRP Ledger", kind: .xrp, nativeSymbol: "XRP",
        rpc: URL(string: "https://xrplcluster.com")!,
        explorer: "https://livenet.xrpl.org",
        blockscout: nil)

    static let bitcoin = Chain(
        id: "bitcoin", name: "Bitcoin", kind: .bitcoin, nativeSymbol: "BTC",
        rpc: URL(string: "https://blockstream.info/api")!,
        explorer: "https://blockstream.info",
        blockscout: nil)

    static let all: [Chain] = [base, ethereum, arbitrum, optimism, polygon, bnb, solana, xrp, bitcoin]

    var evmChainID: BigUInt? {
        if case .evm(let id) = kind { return id }
        return nil
    }

    func transactionURL(_ hash: String) -> URL? {
        URL(string: "\(explorer)/tx/\(hash)")
    }

    func tokenURL(_ contract: String) -> URL? {
        URL(string: "\(explorer)/token/\(contract)")
    }
}
