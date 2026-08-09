import Foundation
import BigInt
import web3swift
import Web3Core

actor ChainService {
    static let shared = ChainService()
    /// One connection per network, opened lazily and kept for reuse.
    private var connections: [String: Web3] = [:]

    // Uniswap v2 on Base — swaps stay on Base because that is where the pool is.
    /// Shared by every Uniswap-V2-compatible router the wallet talks to.
    private let routerABI = """
    [{"name":"swapExactTokensForETH","type":"function","stateMutability":"nonpayable","inputs":[{"name":"amountIn","type":"uint256"},{"name":"amountOutMin","type":"uint256"},{"name":"path","type":"address[]"},{"name":"to","type":"address"},{"name":"deadline","type":"uint256"}],"outputs":[{"name":"amounts","type":"uint256[]"}]},{"name":"swapExactETHForTokens","type":"function","stateMutability":"payable","inputs":[{"name":"amountOutMin","type":"uint256"},{"name":"path","type":"address[]"},{"name":"to","type":"address"},{"name":"deadline","type":"uint256"}],"outputs":[{"name":"amounts","type":"uint256[]"}]},{"name":"swapExactTokensForTokens","type":"function","stateMutability":"nonpayable","inputs":[{"name":"amountIn","type":"uint256"},{"name":"amountOutMin","type":"uint256"},{"name":"path","type":"address[]"},{"name":"to","type":"address"},{"name":"deadline","type":"uint256"}],"outputs":[{"name":"amounts","type":"uint256[]"}]},{"name":"getAmountsOut","type":"function","stateMutability":"view","inputs":[{"name":"amountIn","type":"uint256"},{"name":"path","type":"address[]"}],"outputs":[{"name":"amounts","type":"uint256[]"}]}]
    """

    private func connection(_ chain: Chain) async throws -> Web3 {
        if let existing = connections[chain.id] { return existing }
        guard let chainID = chain.evmChainID else { throw WalletError.invalidAddress }
        let provider = try await Web3HttpProvider(url: chain.rpc, network: .Custom(networkID: chainID))
        let connected = Web3(provider: provider)
        connections[chain.id] = connected
        return connected
    }

    func balance(of token: Token, owner: String) async throws -> Decimal {
        switch token.chain.kind {
        case .solana:
            if let mint = token.contract {
                return try await SolanaService.tokenBalance(owner: owner, mint: mint)
            }
            return try await SolanaService.solBalance(owner: owner)
        case .xrp:
            return try await XRPService.balance(account: owner)
        case .bitcoin:
            return try await BitcoinService.balance(address: owner)
        case .evm:
            break
        }
        let web3 = try await connection(token.chain)
        guard let ownerAddress = EthereumAddress(owner) else { throw WalletError.invalidAddress }
        let raw: BigUInt
        if let contract = token.contract, let tokenAddress = EthereumAddress(contract) {
            let erc20 = ERC20(web3: web3, provider: web3.provider, address: tokenAddress)
            raw = try await erc20.getBalance(account: ownerAddress)
        } else {
            raw = try await web3.eth.getBalance(for: ownerAddress)
        }
        let formatted = Utilities.formatToPrecision(raw, units: .custom(token.decimals), formattingDecimals: 8)
        return Decimal(string: formatted) ?? 0
    }

    func send(token: Token, to recipient: String, amount: String, keystore: BIP32Keystore) async throws -> String {
        let web3 = try await connection(token.chain)

        guard let from = keystore.addresses?.first else { throw WalletError.keystoreUnavailable }
        guard let destination = EthereumAddress(recipient) else { throw WalletError.invalidAddress }
        guard let value = Utilities.parseToBigUInt(amount, decimals: token.decimals), value > 0 else {
            throw WalletError.invalidAmount
        }

        let nonce = try await web3.eth.getTransactionCount(for: from, onBlock: .pending)
        let baseFee = (try? await web3.eth.gasPrice()) ?? BigUInt(100_000_000) // ~0.1 gwei fallback

        // Build the call data and target, then sign locally and broadcast the raw
        // transaction — this bypasses web3swift's pre-flight simulation which Base's
        // public RPC rejects with "OpcodeNotFound".
        let to: EthereumAddress
        let callData: Data
        let ethValue: BigUInt
        if let contractAddress = token.contract.flatMap(EthereumAddress.init) {
            to = contractAddress
            ethValue = 0
            let selector = Data([0xa9, 0x05, 0x9c, 0xbb]) // transfer(address,uint256)
            let paddedTo = Data(repeating: 0, count: 12) + destination.addressData
            let amountBytes = value.serialize()
            let paddedAmount = Data(repeating: 0, count: 32 - amountBytes.count) + amountBytes
            callData = selector + paddedTo + paddedAmount
        } else {
            to = destination
            ethValue = value
            callData = Data()
        }

        var tx = CodableTransaction(
            type: .legacy, to: to, nonce: nonce, chainID: token.chain.evmChainID ?? 0, value: ethValue, data: callData,
            gasLimit: 300_000, gasPrice: baseFee * 2
        )
        tx.from = from

        guard let privateKey = try? keystore.UNSAFE_getPrivateKeyData(password: "", account: from) else {
            throw WalletError.keystoreUnavailable
        }
        try tx.sign(privateKey: privateKey)
        guard let raw = tx.encode() else { throw WalletError.invalidAmount }

        let result = try await web3.eth.send(raw: raw)
        return result.hash
    }

    /// Sign a prepared call locally and broadcast it raw (avoids Base's OpcodeNotFound simulation).
    private func signAndSend(to: EthereumAddress, data: Data, value: BigUInt, nonce: BigUInt,
                             gasPrice: BigUInt, keystore: BIP32Keystore, from: EthereumAddress,
                             on chain: Chain) async throws -> String {
        let web3 = try await connection(chain)
        var tx = CodableTransaction(type: .legacy, to: to, nonce: nonce, chainID: chain.evmChainID ?? 0,
                                    value: value, data: data, gasLimit: 400_000, gasPrice: gasPrice)
        tx.from = from
        guard let pk = try? keystore.UNSAFE_getPrivateKeyData(password: "", account: from) else {
            throw WalletError.keystoreUnavailable
        }
        try tx.sign(privateKey: pk)
        guard let raw = tx.encode() else { throw WalletError.invalidAmount }
        return try await web3.eth.send(raw: raw).hash
    }

    /// The router and wrapped-native pair for a chain, or nil when swapping is
    /// not offered there.
    private func swapVenue(_ chain: Chain) -> (router: EthereumAddress, wrapped: EthereumAddress)? {
        guard let routerAddress = chain.swapRouter.flatMap(EthereumAddress.init),
              let wrappedAddress = chain.wrappedNative.flatMap(EthereumAddress.init) else { return nil }
        return (routerAddress, wrappedAddress)
    }

    /// All pools pair against the wrapped native coin, so token↔token swaps hop
    /// through it: [A, WETH, B].
    private func swapPath(from: Token, to: Token, wrapped: EthereumAddress) -> [EthereumAddress] {
        let a = from.contract.flatMap(EthereumAddress.init) ?? wrapped
        let b = to.contract.flatMap(EthereumAddress.init) ?? wrapped
        if a == wrapped || b == wrapped { return [a, b] }
        return [a, wrapped, b]
    }

    /// How much of `to` you receive for `amountIn` of `from`, via the pool. nil on failure.
    func swapQuote(from: Token, to: Token, amount: String) async throws -> Decimal {
        let amountIn = amount
        guard from.chain == to.chain, let venue = swapVenue(from.chain) else {
            throw WalletError.invalidAddress
        }
        let web3 = try await connection(from.chain)
        guard let value = Utilities.parseToBigUInt(amountIn, decimals: from.decimals), value > 0 else {
            throw WalletError.invalidAmount
        }
        let path = swapPath(from: from, to: to, wrapped: venue.wrapped)
        guard let contract = web3.contract(routerABI, at: venue.router),
              let op = contract.createReadOperation("getAmountsOut", parameters: [value, path]) else {
            throw WalletError.invalidAddress
        }
        let result = try await op.callContractMethod()
        guard let amounts = result["0"] as? [BigUInt], let out = amounts.last else { throw WalletError.invalidAmount }
        let formatted = Utilities.formatToPrecision(out, units: .custom(to.decimals), formattingDecimals: 8)
        return Decimal(string: formatted) ?? 0
    }

    /// Swaps `amountIn` of `from` for `to` through the Uniswap pool. Handles ERC20 approval.
    func swap(from: Token, to: Token, amountIn: String, minOut: BigUInt, keystore: BIP32Keystore) async throws -> String {
        // Both sides must live on the same chain: this is an in-network swap.
        guard from.chain == to.chain, let venue = swapVenue(from.chain) else {
            throw WalletError.invalidAddress
        }
        let chain = from.chain
        let web3 = try await connection(chain)
        guard let owner = keystore.addresses?.first else { throw WalletError.keystoreUnavailable }
        guard let value = Utilities.parseToBigUInt(amountIn, decimals: from.decimals), value > 0 else {
            throw WalletError.invalidAmount
        }
        var nonce = try await web3.eth.getTransactionCount(for: owner, onBlock: .pending)
        let gasPrice = ((try? await web3.eth.gasPrice()) ?? BigUInt(100_000_000)) * 2
        let deadline = BigUInt(9_999_999_999)
        let path = swapPath(from: from, to: to, wrapped: venue.wrapped)
        let router = venue.router

        guard let routerContract = web3.contract(routerABI, at: router) else { throw WalletError.invalidAddress }

        if let tokenAddress = from.contract.flatMap(EthereumAddress.init) {
            // ERC20 → (native or ERC20): approve router, then the matching swap.
            guard let erc20 = web3.contract(Web3.Utils.erc20ABI, at: tokenAddress),
                  let approveData = erc20.createWriteOperation("approve", parameters: [router, value])?
                      .transaction.data else { throw WalletError.invalidAddress }
            _ = try await signAndSend(to: tokenAddress, data: approveData, value: 0, nonce: nonce,
                                      gasPrice: gasPrice, keystore: keystore, from: owner, on: chain)
            nonce += 1
            let method = to.contract == nil ? "swapExactTokensForETH" : "swapExactTokensForTokens"
            guard let swapData = routerContract.createWriteOperation(
                method, parameters: [value, minOut, path, owner, deadline])?.transaction.data else {
                throw WalletError.invalidAddress
            }
            return try await signAndSend(to: router, data: swapData, value: 0, nonce: nonce,
                                         gasPrice: gasPrice, keystore: keystore, from: owner, on: chain)
        } else {
            // Native → ERC20: swapExactETHForTokens (value carries the coin).
            guard let swapData = routerContract.createWriteOperation(
                "swapExactETHForTokens", parameters: [minOut, path, owner, deadline])?.transaction.data else {
                throw WalletError.invalidAddress
            }
            return try await signAndSend(to: router, data: swapData, value: value, nonce: nonce,
                                         gasPrice: gasPrice, keystore: keystore, from: owner, on: chain)
        }
    }

    /// Polls for the transaction receipt. Returns true once mined successfully,
    /// false if it reverted. Gives up (throws) after ~30s.
    func waitForConfirmation(hash: String, on chain: Chain) async throws -> Bool {
        let web3 = try await connection(chain)
        for _ in 0..<15 {
            if let receipt = try? await web3.eth.transactionReceipt(Data.fromHex(hash) ?? Data()) {
                return receipt.status == .ok
            }
            try? await Task.sleep(for: .seconds(2))
        }
        throw WalletError.keystoreUnavailable
    }
}
