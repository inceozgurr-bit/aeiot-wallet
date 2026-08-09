import ReownWalletKit
import SwiftUI

/// A dapp asking to connect. Approving only exposes the wallet address — it
/// grants no authority to move anything, which the sheet says plainly.
struct ConnectionRequestSheet: View {
    let proposal: Session.Proposal
    @Environment(WalletStore.self) private var wallet
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Connection Request").font(.headline)

            VStack(spacing: 6) {
                Text(proposal.proposer.name).font(.title2.bold()).oneLine()
                Text(proposal.proposer.url).font(.footnote).foregroundStyle(.secondary).oneLine()
            }

            VStack(alignment: .leading, spacing: 10) {
                row("wallet.bifold", "Sees your wallet address")
                row("faceid", "Every signature still asks for \(Biometrics.label)")
                row("hand.raised", "Cannot move coins on its own")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()

            Spacer()

            VStack(spacing: 10) {
                Button {
                    Haptic.tap()
                    approve()
                } label: {
                    Text("Connect").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .disabled(working || wallet.activeAddress == nil)

                Button {
                    Haptic.tap()
                    Task { await WalletConnectService.shared.reject(proposal); dismiss() }
                } label: {
                    Text("Cancel").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .disabled(working)
            }
        }
        .padding(20)
        .presentationDetents([.medium])
    }

    private func row(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.appAccent).frame(width: 22)
            Text(text).font(.subheadline)
        }
    }

    private func approve() {
        guard let address = wallet.activeAddress else { return }
        working = true
        Task {
            await WalletConnectService.shared.approve(proposal, address: address)
            working = false
            dismiss()
        }
    }
}

/// A dapp asking for a signature. The payload is shown in full before anything
/// is signed, and signing always goes through a fresh biometric check.
struct SignatureRequestSheet: View {
    let request: Request
    @Environment(WalletStore.self) private var wallet
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Signature Request").font(.headline)
            Text(request.method).font(.footnote.monospaced()).foregroundStyle(.secondary).oneLine()

            ScrollView {
                Text(WalletConnectService.readableMessage(for: request))
                    .font(.footnote.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)
            .glassCard()

            Label("Only sign this if you asked the app for it.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(Color.appAccent)

            if let error {
                Text(error).font(.caption).foregroundStyle(Color.appAccent)
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    Haptic.tap()
                    sign()
                } label: {
                    Text("Sign with \(Biometrics.label)")
                        .frame(maxWidth: .infinity).padding(.vertical, 6).oneLine()
                }
                .buttonStyle(.glassProminent)
                .disabled(working)

                Button {
                    Haptic.tap()
                    Task { await WalletConnectService.shared.decline(request); dismiss() }
                } label: {
                    Text("Cancel").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .disabled(working)
            }
        }
        .padding(20)
    }

    private func sign() {
        working = true
        Task {
            do {
                let result = try await WalletConnectService.shared.sign(request, using: wallet)
                await WalletConnectService.shared.respond(request, result: result)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                working = false
            }
        }
    }
}

/// The apps this wallet is currently connected to, and the way to add one.
struct ConnectedAppsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var service = WalletConnectService.shared
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Haptic.tap()
                        showScanner = true
                    } label: {
                        Label("Scan an app's QR code", systemImage: "qrcode.viewfinder")
                    }
                } footer: {
                    Text("Open the app in a browser, choose WalletConnect, then scan the code it shows.")
                }

                if !service.sessions.isEmpty {
                    Section("Connected Apps") {
                        ForEach(service.sessions, id: \.topic) { session in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.peer.name).font(.headline).oneLine()
                                    Text(session.peer.url).font(.caption).foregroundStyle(.secondary).oneLine()
                                }
                                Spacer()
                                Button("Disconnect") {
                                    Haptic.tap()
                                    Task { await service.disconnect(session) }
                                }
                                .buttonStyle(.borderless)
                                .font(.footnote)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Connected Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { scanned in
                    showScanner = false
                    Task { await service.pair(scanned) }
                }
            }
        }
    }
}
