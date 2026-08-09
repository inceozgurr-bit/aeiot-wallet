import SwiftUI

/// Terms and privacy text. Kept factual: the app has no server, and the only
/// data that ever leaves the device is what the listed public APIs need.
struct LegalView: View {
    enum Document {
        case terms, privacy

        var title: LocalizedStringKey {
            switch self {
            case .terms: "Terms of Use"
            case .privacy: "Privacy Policy"
            }
        }

        var sections: [(LocalizedStringKey, LocalizedStringKey)] {
            switch self {
            case .terms: Document.termsSections
            case .privacy: Document.privacySections
            }
        }

        private static let termsSections: [(LocalizedStringKey, LocalizedStringKey)] = [
            ("You hold the keys",
             "AEIOT Wallet is a self-custody wallet. Your 12-word recovery phrase is created on this device and stored only in its Keychain. Nobody else — including the developer — has a copy or any way to recover it."),
            ("Losing the phrase means losing the coins",
             "If you delete the app without a backup, or lose the 12 words, your coins cannot be restored by anyone. Write the words down and keep them offline."),
            ("Transfers are final",
             "Transactions on the Base network cannot be cancelled or reversed. Always check the recipient address before confirming. Sending to a wrong address means the coins are gone."),
            ("Not financial advice",
             "Prices shown in the app come from public sources and can be wrong, delayed, or missing. Nothing in this app is investment advice. You are responsible for your own decisions."),
            ("No warranty",
             "The app is provided as is, without warranty of any kind. The developer is not liable for lost coins, network failures, incorrect prices, or damages arising from use of the app."),
            ("AEIOT the coin",
             "AEIOT is a fixed-supply ERC-20 token on the Base network with a total supply of 1,150,115. No further tokens can be created. It carries no promise of value or return."),
        ]

        private static let privacySections: [(LocalizedStringKey, LocalizedStringKey)] = [
            ("No accounts, no tracking",
             "The app has no sign-up, no user account and no server of its own. It contains no analytics, advertising or tracking of any kind."),
            ("What stays on your device",
             "Your recovery phrases, wallet names and saved addresses are stored in this device's Keychain and in local app settings. They are never uploaded anywhere."),
            ("What leaves your device",
             "To show balances and history, the app sends your public wallet addresses to the networks it supports — Base, Ethereum, Arbitrum, Optimism, Polygon, BNB Chain, Solana, the XRP Ledger and Bitcoin — and to the public explorers that list past transactions. To show prices it requests public market data from CoinGecko. These requests carry no name, e-mail or device identifier."),
            ("Connecting to other apps",
             "When you connect to an app through WalletConnect, its relay passes encrypted messages between this wallet and that app, and the app is told your wallet address. It can ask you to sign, but every signature needs your approval and your biometrics. Your recovery phrase is never shared."),
            ("Public blockchain",
             "These networks are public. Any address and transaction, including yours, can be viewed by anyone through a block explorer. This is a property of the blockchain, not of this app."),
            ("Camera",
             "The camera is used only to scan a recipient QR code while the Send screen is open. Nothing is recorded or stored."),
            ("Face ID",
             "Biometric checks are handled by iOS. The app is only told whether the check passed; it never sees your biometric data."),
            ("Contact",
             "Questions about this policy: ince.ozgurr@gmail.com"),
        ]
    }

    let document: Document

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.0)
                            .font(.headline)
                        Text(section.1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
