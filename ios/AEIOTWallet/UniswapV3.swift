import BigInt
import Foundation

/// Call data for the three Uniswap V3 functions this wallet needs.
///
/// Written out by hand rather than through an ABI file: every one of these
/// takes a tuple parameter, which the ABI encoder in web3swift does not accept,
/// and building the bytes here keeps them testable against known-good values.
///
/// V3 is used where the V2 pools quote badly — measured on Arbitrum, a V2 quote
/// came back 7.8% under spot and SushiSwap's 25% under, while V3 was within
/// 0.06%. Where V2 is healthy (Base, and the AEIOT pool itself) it stays.
enum UniswapV3 {
    /// Fee tiers, in hundredths of a basis point. 0.05% holds the deepest
    /// stablecoin and ETH liquidity; 0.3% is the fallback for thinner pairs.
    static let lowFee: BigUInt = 500
    static let mediumFee: BigUInt = 3000

    /// `quoteExactInputSingle((tokenIn, tokenOut, amountIn, fee, sqrtPriceLimit))`
    /// Returns how much comes out, straight from the pool's own maths.
    static func quoteExactInputSingle(tokenIn: String, tokenOut: String,
                                      amountIn: BigUInt, fee: BigUInt) -> Data {
        selector("c6a5026a")
            + word(address: tokenIn) + word(address: tokenOut)
            + word(amountIn) + word(fee) + word(0)
    }

    /// `exactInputSingle((tokenIn, tokenOut, fee, recipient, amountIn, amountOutMinimum, sqrtPriceLimit))`
    ///
    /// `amountOutMinimum` is the whole protection: the pool reverts rather than
    /// fill below it. SwapRouter02 dropped the deadline parameter, so that floor
    /// is what stands between the user and a sandwich.
    static func exactInputSingle(tokenIn: String, tokenOut: String, fee: BigUInt,
                                 recipient: String, amountIn: BigUInt,
                                 amountOutMinimum: BigUInt) -> Data {
        selector("04e45aaf")
            + word(address: tokenIn) + word(address: tokenOut) + word(fee)
            + word(address: recipient) + word(amountIn) + word(amountOutMinimum) + word(0)
    }

    /// `unwrapWETH9(amountMinimum, recipient)` — turns the WETH a swap produced
    /// back into native coin. Without it someone swapping to ETH would receive
    /// WETH, which this wallet does not list, and their money would look gone.
    static func unwrapWETH9(amountMinimum: BigUInt, recipient: String) -> Data {
        selector("49404b7c") + word(amountMinimum) + word(address: recipient)
    }

    /// `multicall(bytes[])` — swap and unwrap in one transaction, so a failure
    /// at either step reverts both.
    static func multicall(_ calls: [Data]) -> Data {
        var out = selector("ac9650d8")
        out += word(0x20)                     // offset to the array
        out += word(BigUInt(calls.count))
        // Offsets are measured from the start of the array's contents.
        var offset = BigUInt(32 * calls.count)
        for call in calls {
            out += word(offset)
            offset += BigUInt(32 + paddedLength(call.count))
        }
        for call in calls {
            out += word(BigUInt(call.count))
            out += call + Data(repeating: 0, count: paddedLength(call.count) - call.count)
        }
        return out
    }

    /// The recipient that keeps funds inside the router so a following step —
    /// the unwrap — can act on them. Uniswap's own constant for "this contract".
    static let routerAsRecipient = "0x0000000000000000000000000000000000000002"

    // MARK: Encoding

    private static func selector(_ hex: String) -> Data {
        Data(stride(from: 0, to: hex.count, by: 2).compactMap {
            UInt8(hex.dropFirst($0).prefix(2), radix: 16)
        })
    }

    private static func word(_ value: BigUInt) -> Data {
        let bytes = value.serialize()
        return Data(repeating: 0, count: 32 - bytes.count) + bytes
    }

    private static func word(_ value: Int) -> Data { word(BigUInt(value)) }

    private static func word(address: String) -> Data {
        let hex = address.hasPrefix("0x") ? String(address.dropFirst(2)) : address
        let bytes = Data(stride(from: 0, to: hex.count, by: 2).compactMap {
            UInt8(hex.dropFirst($0).prefix(2), radix: 16)
        })
        return Data(repeating: 0, count: 32 - bytes.count) + bytes
    }

    private static func paddedLength(_ length: Int) -> Int {
        length % 32 == 0 ? length : length + (32 - length % 32)
    }
}
