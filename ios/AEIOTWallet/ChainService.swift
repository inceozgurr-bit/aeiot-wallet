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

    /// `owners` is a list because Bitcoin spreads a wallet's funds across many
    /// addresses; every other network passes a single one.
    func balance(of token: Token, owners: [String]) async throws -> Decimal {
        if case .bitcoin = token.chain.kind {
            return await BitcoinService.balance(addresses: owners)
        }
        guard let owner = owners.first else { throw WalletError.invalidAddress }
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
        // Never fall back to chain 0: that yields a pre-EIP-155 signature, valid
        // on every EVM chain, so the same transaction could be replayed on one
        // the user never intended.
        guard let chainID = chain.evmChainID else { throw WalletError.invalidAddress }
        var tx = CodableTransaction(type: .legacy, to: to, nonce: nonce, chainID: chainID,
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
        let out = try await amountOut(from: from, to: to, amount: amount)
        let formatted = Utilities.formatToPrecision(out, units: .custom(to.decimals), formattingDecimals: 8)
        return Decimal(string: formatted) ?? 0
    }

    /// Accept at worst 15% below the quote — the AEIOT pool is small, so honest
    /// price movement between quote and mining is real.
    private static let slippageNumerator = 85

    /// Swaps through Uniswap V3. Three shapes, because the router only speaks
    /// in wrapped coin: paying with the native coin sends it as `value`, and
    /// receiving it needs a second call to unwrap, bundled so either both steps
    /// happen or neither does.
    private func v3Swap(from: Token, to: Token, amountIn: BigUInt, minOut: BigUInt,
                        keystore: BIP32Keystore, owner: EthereumAddress, nonce: BigUInt,
                        gasPrice: BigUInt, on chain: Chain) async throws -> String {
        guard let routerAddress = chain.v3Router, let router = EthereumAddress(routerAddress),
              let wrapped = chain.wrappedNative else { throw WalletError.invalidAddress }
        let tokenIn = from.contract ?? wrapped
        let tokenOut = to.contract ?? wrapped
        let fee = try await v3Fee(tokenIn: tokenIn, tokenOut: tokenOut, amountIn: amountIn, on: chain)
        var nonce = nonce

        // Paying with a token means letting the router move it first.
        if let contract = from.contract, let tokenAddress = EthereumAddress(contract) {
            let web3 = try await connection(chain)
            guard let erc20 = web3.contract(Web3.Utils.erc20ABI, at: tokenAddress),
                  let approveData = erc20.createWriteOperation("approve", parameters: [router, amountIn])?
                      .transaction.data else { throw WalletError.invalidAddress }
            let approveHash = try await signAndSend(to: tokenAddress, data: approveData, value: 0,
                                                    nonce: nonce, gasPrice: gasPrice,
                                                    keystore: keystore, from: owner, on: chain)
            guard try await waitForConfirmation(hash: approveHash, on: chain) else {
                throw WalletError.approvalFailed
            }
            nonce += 1
        }

        let wantsNativeOut = to.contract == nil
        let swapCall = UniswapV3.exactInputSingle(
            tokenIn: tokenIn, tokenOut: tokenOut, fee: fee,
            // Receiving native coin: the router keeps the WETH so it can unwrap.
            recipient: wantsNativeOut ? UniswapV3.routerAsRecipient : owner.address,
            amountIn: amountIn, amountOutMinimum: minOut)
        let data = wantsNativeOut
            ? UniswapV3.multicall([swapCall,
                                   UniswapV3.unwrapWETH9(amountMinimum: minOut,
                                                         recipient: owner.address)])
            : swapCall
        return try await signAndSend(to: router, data: data,
                                     value: from.contract == nil ? amountIn : 0,
                                     nonce: nonce, gasPrice: gasPrice,
                                     keystore: keystore, from: owner, on: chain)
    }

    /// Which fee tier actually holds this pair, decided by asking both.
    private func v3Fee(tokenIn: String, tokenOut: String,
                       amountIn: BigUInt, on chain: Chain) async throws -> BigUInt {
        guard let quoter = chain.v3Quoter else { throw WalletError.invalidAddress }
        for fee in [UniswapV3.lowFee, UniswapV3.mediumFee] {
            let data = UniswapV3.quoteExactInputSingle(tokenIn: tokenIn, tokenOut: tokenOut,
                                                       amountIn: amountIn, fee: fee)
            if let out = try? await ethCall(to: quoter, data: data, on: chain), out > 0 { return fee }
        }
        throw WalletError.invalidAmount
    }

    /// Asks a Uniswap V3 pool what comes out, trying the deep 0.05% tier first
    /// and falling back to 0.30% for pairs that only exist there.
    private func v3AmountOut(from: Token, to: Token, amountIn: BigUInt) async throws -> BigUInt {
        let chain = from.chain
        guard let quoter = chain.v3Quoter, let wrapped = chain.wrappedNative else {
            throw WalletError.invalidAddress
        }
        // A native coin is quoted as its wrapped form; the pools only hold that.
        let tokenIn = from.contract ?? wrapped
        let tokenOut = to.contract ?? wrapped
        for fee in [UniswapV3.lowFee, UniswapV3.mediumFee] {
            let data = UniswapV3.quoteExactInputSingle(tokenIn: tokenIn, tokenOut: tokenOut,
                                                       amountIn: amountIn, fee: fee)
            if let out = try? await ethCall(to: quoter, data: data, on: chain), out > 0 {
                return out
            }
        }
        throw WalletError.invalidAmount
    }

    /// A raw `eth_call` returning the first 32-byte word. The quoter takes a
    /// tuple, which web3swift's ABI encoder will not build, so the call data is
    /// assembled by hand in `UniswapV3`.
    private func ethCall(to address: String, data: Data, on chain: Chain) async throws -> BigUInt {
        var request = URLRequest(url: chain.rpc)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let hex = "0x" + data.map { String(format: "%02x", $0) }.joined()
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "eth_call",
            "params": [["to": address, "data": hex], "latest"],
        ])
        let (body, _) = try await URLSession.shared.data(for: request)
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let result = root["result"] as? String, result.count >= 66,
              let value = BigUInt(String(result.dropFirst(2).prefix(64)), radix: 16) else {
            throw WalletError.invalidAmount
        }
        return value
    }

    /// The pool's own answer, in the token's smallest unit. Kept as BigUInt so
    /// the slippage floor never has to survive a trip through a formatted
    /// string: that rounding could fail and silently leave no floor at all.
    private func amountOut(from: Token, to: Token, amount: String) async throws -> BigUInt {
        guard from.chain == to.chain, let venue = swapVenue(from.chain) else {
            throw WalletError.invalidAddress
        }
        let web3 = try await connection(from.chain)
        guard let value = Utilities.parseToBigUInt(amount, decimals: from.decimals), value > 0 else {
            throw WalletError.invalidAmount
        }
        if from.chain.usesV3 { return try await v3AmountOut(from: from, to: to, amountIn: value) }
        let path = swapPath(from: from, to: to, wrapped: venue.wrapped)
        guard let contract = web3.contract(routerABI, at: venue.router),
              let op = contract.createReadOperation("getAmountsOut", parameters: [value, path]) else {
            throw WalletError.invalidAddress
        }
        let result = try await op.callContractMethod()
        guard let amounts = result["0"] as? [BigUInt], let out = amounts.last else { throw WalletError.invalidAmount }
        return out
    }

    /// Roughly what the network will charge for one transfer, in the chain's own
    /// coin. Shown before confirming: without a number on screen a fee spike —
    /// or a hostile fee estimate — burns the balance invisibly.
    func estimatedFee(for token: Token) async -> Decimal? {
        switch token.chain.kind {
        case .evm:
            guard let web3 = try? await connection(token.chain) else { return nil }
            let gasPrice = ((try? await web3.eth.gasPrice()) ?? BigUInt(100_000_000)) * 2
            // A plain transfer costs 21k gas; moving an ERC-20 roughly 65k.
            let gas = BigUInt(token.contract == nil ? 21_000 : 65_000)
            let formatted = Utilities.formatToPrecision(gasPrice * gas, units: .ether,
                                                        formattingDecimals: 8)
            return Decimal(string: formatted)
        case .bitcoin:
            // One input and two outputs, the shape BitcoinService builds.
            let vsize = Double(10 + 68 + 31 * 2)
            return Decimal(await BitcoinService.feeRate() * vsize) / 100_000_000
        case .solana:
            return Decimal(5_000) / 1_000_000_000
        case .xrp:
            return Decimal(12) / 1_000_000
        }
    }

    /// Swaps `amountIn` of `from` for `to` through the Uniswap pool. Handles ERC20 approval.
    func swap(from: Token, to: Token, amountIn: String, keystore: BIP32Keystore) async throws -> String {
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
        // Priced at signing time, not when the quote was last shown, and floored
        // in whole units so no rounding can wipe the protection out. Without a
        // real floor a sandwich bot can take almost the whole trade.
        let expected = try await amountOut(from: from, to: to, amount: amountIn)
        let minOut = expected * BigUInt(Self.slippageNumerator) / 100
        guard minOut > 0 else { throw WalletError.invalidAmount }
        var nonce = try await web3.eth.getTransactionCount(for: owner, onBlock: .pending)
        let gasPrice = ((try? await web3.eth.gasPrice()) ?? BigUInt(100_000_000)) * 2
        if chain.usesV3 {
            return try await v3Swap(from: from, to: to, amountIn: value, minOut: minOut,
                                    keystore: keystore, owner: owner, nonce: nonce,
                                    gasPrice: gasPrice, on: chain)
        }
        // A swap that cannot be mined soon should expire, not sit in the mempool
        // waiting for a moment when it is profitable to somebody else.
        let deadline = BigUInt(Date().timeIntervalSince1970 + 20 * 60)
        let path = swapPath(from: from, to: to, wrapped: venue.wrapped)
        let router = venue.router

        guard let routerContract = web3.contract(routerABI, at: router) else { throw WalletError.invalidAddress }

        if let tokenAddress = from.contract.flatMap(EthereumAddress.init) {
            // ERC20 → (native or ERC20): approve router, then the matching swap.
            guard let erc20 = web3.contract(Web3.Utils.erc20ABI, at: tokenAddress),
                  let approveData = erc20.createWriteOperation("approve", parameters: [router, value])?
                      .transaction.data else { throw WalletError.invalidAddress }
            let approveHash = try await signAndSend(to: tokenAddress, data: approveData, value: 0, nonce: nonce,
                                                    gasPrice: gasPrice, keystore: keystore, from: owner, on: chain)
            // Sending the swap on the next nonce before the approval is mined
            // burns gas on a call the router must reject, and on tokens like
            // USDT a leftover allowance then blocks every later attempt.
            guard try await waitForConfirmation(hash: approveHash, on: chain) else {
                throw WalletError.approvalFailed
            }
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
