import BigInt
import Foundation
import Testing
@testable import AEIOTWallet

/// The V3 call data is assembled byte by byte, so these check the layout the
/// router actually expects. A misplaced word here does not fail loudly — it
/// sends a transaction that swaps the wrong amount, or pays the wrong address.
struct UniswapV3Tests {
    static let weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"
    static let usdc = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"
    static let owner = "0x1111111111111111111111111111111111111111"

    /// Selector plus five 32-byte words — the shape a live Arbitrum quoter
    /// answered with a correct price while this was being written.
    @Test("Quote call data has the layout the quoter accepts")
    func quoteLayout() {
        let data = UniswapV3.quoteExactInputSingle(
            tokenIn: Self.weth, tokenOut: Self.usdc,
            amountIn: BigUInt(10).power(18), fee: UniswapV3.lowFee)
        #expect(data.count == 4 + 5 * 32)
        #expect(hex(data.prefix(4)) == "c6a5026a")
        // Addresses sit right-aligned in their word, zero-padded in front.
        #expect(hex(word(data, 0)).hasSuffix(Self.weth.dropFirst(2).lowercased()))
        #expect(hex(word(data, 1)).hasSuffix(Self.usdc.dropFirst(2).lowercased()))
        #expect(BigUInt(hex(word(data, 2)), radix: 16) == BigUInt(10).power(18))
        #expect(BigUInt(hex(word(data, 3)), radix: 16) == 500)
    }

    /// The minimum-out word is the only thing standing between the user and a
    /// sandwich, so its position must be exact.
    @Test("Swap call data carries recipient and minimum in the right slots")
    func swapLayout() {
        let data = UniswapV3.exactInputSingle(
            tokenIn: Self.weth, tokenOut: Self.usdc, fee: UniswapV3.lowFee,
            recipient: Self.owner, amountIn: 1_000, amountOutMinimum: 850)
        #expect(data.count == 4 + 7 * 32)
        #expect(hex(data.prefix(4)) == "04e45aaf")
        #expect(hex(word(data, 3)).hasSuffix(Self.owner.dropFirst(2)))
        #expect(BigUInt(hex(word(data, 4)), radix: 16) == 1_000)
        #expect(BigUInt(hex(word(data, 5)), radix: 16) == 850)
    }

    /// Swapping into native coin bundles the swap with an unwrap. Getting the
    /// dynamic-array offsets wrong makes the router read garbage.
    @Test("Multicall wraps both calls with correct offsets")
    func multicallLayout() throws {
        let swap = UniswapV3.exactInputSingle(
            tokenIn: Self.usdc, tokenOut: Self.weth, fee: UniswapV3.lowFee,
            recipient: UniswapV3.routerAsRecipient, amountIn: 1_000, amountOutMinimum: 1)
        let unwrap = UniswapV3.unwrapWETH9(amountMinimum: 1, recipient: Self.owner)
        let data = UniswapV3.multicall([swap, unwrap])

        #expect(hex(data.prefix(4)) == "ac9650d8")
        #expect(BigUInt(hex(word(data, 0)), radix: 16) == 32)   // offset to the array
        #expect(BigUInt(hex(word(data, 1)), radix: 16) == 2)    // two calls

        // The first element starts after both offset words. The second starts
        // after the first element's length word plus its body padded up to a
        // 32-byte boundary — the swap call is 228 bytes, so it pads to 256, and
        // an offset computed from the unpadded length would point mid-word.
        let padded = swap.count.isMultiple(of: 32)
            ? swap.count : swap.count + (32 - swap.count % 32)
        #expect(BigUInt(hex(word(data, 2)), radix: 16) == 64)
        #expect(BigUInt(hex(word(data, 3)), radix: 16) == 64 + 32 + BigUInt(padded))

        // Each element declares its own true length.
        #expect(BigUInt(hex(word(data, 4)), radix: 16) == BigUInt(swap.count))
    }

    private func word(_ data: Data, _ index: Int) -> Data {
        let start = data.startIndex + 4 + index * 32
        return data[start..<start + 32]
    }

    private func hex<C: Collection>(_ bytes: C) -> String where C.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
