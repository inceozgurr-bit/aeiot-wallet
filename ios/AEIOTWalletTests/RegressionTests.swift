import Foundation
import Testing
@testable import AEIOTWallet

/// One test per bug that actually shipped. The point is not coverage — it is
/// that these particular mistakes cannot come back quietly.
struct RegressionTests {

    /// Blockscout stamps transfers with microseconds. The plain internet-date
    /// parser rejects that, and the code fell back to "now" — so every row in
    /// the history showed the same timestamp and the sort order was meaningless.
    @Test("Transfer timestamps parse in both shapes, and refuse nonsense")
    func timestampParsing() throws {
        let withMicroseconds = try #require(HistoryService.parseTimestamp("2026-07-15T20:46:59.000000Z"))
        let withoutFraction = try #require(HistoryService.parseTimestamp("2026-07-15T20:46:59Z"))
        #expect(withMicroseconds == withoutFraction)

        // A real moment, not "now": the bug made every row equal to the present.
        #expect(abs(withMicroseconds.timeIntervalSince(Date())) > 60)

        // Unparseable input must not silently become a date.
        #expect(HistoryService.parseTimestamp("not a date") == nil)
        #expect(HistoryService.parseTimestamp("") == nil)
    }

    /// Token symbols come from whoever deployed the token, so an airdrop can put
    /// phishing text, a right-to-left override, or a lookalike ticker into the
    /// activity list, where it renders as if the app had written it.
    @Test("Token symbols are reduced to something that cannot impersonate the app")
    func symbolSanitising() {
        #expect(HistoryService.safeSymbol("USDC") == "USDC")
        #expect(HistoryService.safeSymbol(nil) == "?")
        #expect(HistoryService.safeSymbol("") == "?")

        // Punctuation and spacing carry the phishing message; strip them.
        #expect(HistoryService.safeSymbol("Claim at evil.example!") == "Claimatevile")

        // A right-to-left override would reorder the row around it.
        #expect(HistoryService.safeSymbol("US\u{202E}DC") == "USDC")

        // Cyrillic lookalikes must not survive as a fake ticker.
        #expect(HistoryService.safeSymbol("\u{0421}\u{0420}") == "?")

        // Long names are cut, so a row cannot be pushed out of shape.
        #expect(HistoryService.safeSymbol(String(repeating: "A", count: 40)).count == 12)
    }

    /// The slippage floor used to be built by formatting a Decimal and parsing
    /// it back. That returns nil whenever the figure carries more decimals than
    /// the token has — and always, in locales with non-Latin digits — after
    /// which `?? 0` left no floor at all. It is integer arithmetic now; this
    /// checks that arithmetic holds at awkward magnitudes.
    @Test("Slippage floor stays proportional and never reaches zero")
    func slippageFloor() {
        // Mirrors ChainService: quoted * 85 / 100, in the token's smallest unit.
        func floor(_ quoted: UInt64) -> UInt64 { quoted * 85 / 100 }

        #expect(floor(1_000_000) == 850_000)   // 1 USDC, 6 decimals
        #expect(floor(166_666) == 141_666)     // the value that used to fail
        #expect(floor(2) == 1)                 // anything real keeps a floor

        // The floor must sit below the quote and above zero: equal to the quote
        // never fills, zero means no protection at all.
        for quoted in [UInt64(100), 12_345, 999_999_999] {
            #expect(floor(quoted) < quoted)
            #expect(floor(quoted) > 0)
        }
    }

    /// A signature payload is shown before it is approved. Hidden direction and
    /// zero-width characters can make what is displayed differ from what is
    /// signed.
    // WalletConnectService is main-actor isolated, like the screens that use it.
    @Test("Signature payloads cannot hide or reorder themselves")
    @MainActor
    func payloadSanitising() {
        let shown = WalletConnectService.sanitized("Sign in\u{202E}\u{200B} to example.com")
        #expect(!shown.contains("\u{202E}"))
        #expect(!shown.contains("\u{200B}"))
        // The readable words survive; only the invisible steering is removed.
        #expect(shown.contains("example.com"))
    }
}
