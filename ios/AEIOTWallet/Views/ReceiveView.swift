import SwiftUI
import CoreImage.CIFilterBuiltins

struct ReceiveView: View {
    @Environment(WalletStore.self) private var wallet
    @State private var family = AddressFamily.evm
    @State private var copied = false
    @State private var isDeriving = false

    /// The two address shapes this wallet holds. Every EVM network shares one.
    private enum AddressFamily: String, CaseIterable, Identifiable {
        case evm, bitcoin, solana, xrp
        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .evm: "EVM"
            case .bitcoin: "BTC"
            case .solana: "SOL"
            case .xrp: "XRP"
            }
        }

        var chain: Chain {
            switch self {
            case .evm: .base
            case .bitcoin: .bitcoin
            case .solana: .solana
            case .xrp: .xrp
            }
        }
    }

    private var address: String? { wallet.address(for: family.chain) }

    var body: some View {
        VStack(spacing: 20) {
            Text("Receive").font(.title2.bold())

            Picker("Network", selection: $family) {
                ForEach(AddressFamily.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Text(explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let address {
                if let qr = qrImage(for: address) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .padding(12)
                        .background(.white, in: .rect(cornerRadius: 20))
                }
                Text(address)
                    .font(.caption.monospaced())
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))

                Button {
                    Haptic.tap()
                    SecurePasteboard.copy(address)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy Address",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
            } else {
                // Wallets made before these networks need the address derived once.
                Button {
                    Haptic.tap()
                    deriveMissingAddress()
                } label: {
                    Text(isDeriving ? "Creating…" : "Create Address")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .disabled(isDeriving)
                .padding(.top, 40)
            }
            Spacer()
        }
        .padding(24)
        .padding(.top, 60)
        .onChange(of: family) { _, _ in copied = false }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
    }

    private var explanation: LocalizedStringKey {
        switch family {
        case .evm:
            "One address for Base, Ethereum, Arbitrum, Optimism, Polygon and BNB Chain. Make sure the sender uses the same network."
        case .solana:
            "Your Solana address. It is different from the 0x… one — only send SOL or Solana tokens here."
        case .xrp:
            "Your XRP address. The first transfer must be at least the network's account reserve, otherwise the account is not created."
        case .bitcoin:
            "Your Bitcoin address. Only send BTC on the Bitcoin network here — not cbBTC or WBTC."
        }
    }

    private func deriveMissingAddress() {
        isDeriving = true
        Task {
            await wallet.backfillAddresses()
            isDeriving = false
        }
    }

    /// A CIContext allocates a Metal device and command queue, so building one
    /// per call — from a body that redraws on every network switch and every
    /// "Copied" flash — was the most expensive thing on this screen.
    private static let ciContext = CIContext()

    private func qrImage(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = Self.ciContext.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
