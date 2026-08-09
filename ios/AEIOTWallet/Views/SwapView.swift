import SwiftUI
import BigInt
import Web3Core

struct SwapView: View {
    @Environment(WalletStore.self) private var wallet
    @Environment(\.dismiss) private var dismiss
    var onDone: () -> Void

    @State private var chain = Chain.base
    @State private var fromToken = Token.aeiot
    @State private var toToken = Token.swappable.first { $0.chain == .base && $0.symbol == "ETH" }!
    @State private var amount = ""
    @State private var quote: Decimal?
    @State private var isSwapping = false
    @State private var txHash: String?
    @State private var errorMessage: String?

    /// Swaps stay inside one network, so both sides come from this list.
    private var chainTokens: [Token] { Token.swappable.filter { $0.chain == chain } }

    private var normalizedAmount: String { amount.replacingOccurrences(of: ",", with: ".") }

    private var actionKey: LocalizedStringKey { isSwapping ? "Swapping…" : "Swap" }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                if let txHash { sentView(txHash) } else { form }
            }
            .navigationTitle("Swap")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var form: some View {
        VStack(spacing: 16) {
            networkPicker
            tokenField(label: "You pay", token: fromToken, editable: true)
            Button {
                Haptic.tap()
                swap(&fromToken, &toToken)
                quote = nil
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
            }
            tokenField(label: "You receive (estimated)", token: toToken, editable: false)

            Text("Swaps route through Uniswap pools on Base. Price moves with pool size; small pools shift a lot.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)

            Spacer()

            Button {
                Haptic.tap()
                performSwap()
            } label: {
                Text(actionKey)
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .disabled(isSwapping || amount.isEmpty || quote == nil)

            if let errorMessage {
                Text(errorMessage).foregroundStyle(Color.appAccent).font(.footnote).multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .task(id: "\(fromToken.symbol)-\(toToken.symbol)-\(normalizedAmount)") { await refreshQuote() }
    }

    /// Only networks whose pools were verified to quote at market price.
    private var networkPicker: some View {
        Menu {
            ForEach(Token.swappableChains) { option in
                Button {
                    Haptic.tap()
                    selectChain(option)
                } label: {
                    if option == chain {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(option.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .foregroundStyle(Color.appAccent)
                Text(chain.name).font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .tint(.primary)
    }

    private func selectChain(_ newChain: Chain) {
        chain = newChain
        let tokens = Token.swappable.filter { $0.chain == newChain }
        fromToken = tokens.first ?? fromToken
        toToken = tokens.dropFirst().first ?? fromToken
        amount = ""
        quote = nil
    }

    private func tokenField(label: LocalizedStringKey, token: Token, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack {
                Menu {
                    ForEach(chainTokens.filter { $0.symbol != (editable ? toToken : fromToken).symbol }) { option in
                        Button {
                            Haptic.tap()
                            if editable { fromToken = option } else { toToken = option }
                            quote = nil
                        } label: {
                            Text(option.symbol)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        TokenLogo(token: token, size: 32)
                        Text(token.symbol).font(.headline).foregroundStyle(.primary)
                        Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if editable {
                    TextField("0", text: $amount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title3.monospacedDigit())
                } else {
                    Text(quote.map { $0.formatted(.number.precision(.fractionLength(0...6))) } ?? "—")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func sentView(_ hash: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(Color.appAccent)
            Text("Swap Sent").font(.title2.bold())
            if let url = Chain.base.transactionURL(hash) {
                Link("View in Explorer", destination: url).font(.footnote)
            }
            Spacer()
            Button {
                onDone(); dismiss()
            } label: {
                Text("Back to Home").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(24)
    }

    private func refreshQuote() async {
        guard !normalizedAmount.isEmpty, Decimal(string: normalizedAmount) ?? 0 > 0 else { quote = nil; return }
        // Typing "1000" used to fire four separate on-chain calls. The task is
        // keyed on the amount, so a newer keystroke cancels this sleep before it
        // ever reaches the network.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        quote = try? await ChainService.shared.swapQuote(from: fromToken, to: toToken, amount: normalizedAmount)
    }

    private func performSwap() {
        isSwapping = true
        errorMessage = nil
        Task {
            guard await wallet.authenticate(reason: String.loc("Confirm this swap")) else {
                errorMessage = String.loc("Authentication failed."); isSwapping = false; return
            }
            do {
                let keystore = try await wallet.loadKeystore()
                txHash = try await ChainService.shared.swap(
                    from: fromToken, to: toToken, amountIn: normalizedAmount, keystore: keystore)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSwapping = false
        }
    }

    private func swap<T>(_ a: inout T, _ b: inout T) { let t = a; a = b; b = t }
}
