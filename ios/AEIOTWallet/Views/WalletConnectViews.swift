import ReownWalletKit
import SwiftUI

/// A dapp asking to connect. Approving only exposes the wallet address — it
/// grants no authority to move anything, which the sheet says plainly.
struct ConnectionRequestSheet: View {
    let pending: WalletConnectService.Pending<Session.Proposal>
    @Environment(WalletStore.self) private var wallet
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    private var proposal: Session.Proposal { pending.body }

    var body: some View {
        VStack(spacing: 20) {
            Text("Connection Request").font(.headline)

            VStack(spacing: 6) {
                Text(proposal.proposer.name).font(.title2.bold()).oneLine()
                Text(proposal.proposer.url).font(.footnote).foregroundStyle(.secondary).oneLine()
            }

            if pending.isScam {
                Label("This site is flagged as fraudulent. Do not sign.", systemImage: "hand.raised.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.appAccent)
                    .padding(10)
                    .background(Color.appAccent.opacity(0.12), in: .rect(cornerRadius: 10))
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
    let pending: WalletConnectService.Pending<Request>
    @Environment(WalletStore.self) private var wallet
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var error: String?
    @State private var reachedEnd = false

    private var request: Request { pending.body }
    private var message: String { WalletConnectService.readableMessage(for: request) }

    var body: some View {
        VStack(spacing: 14) {
            Text("Signature Request").font(.headline)

            // Who is asking, and whether the relay could vouch for them. Without
            // this the same sheet appears for a real site and for a clone of it.
            VStack(spacing: 4) {
                Text(WalletConnectService.shared.dappName(for: request))
                    .font(.subheadline.bold()).oneLine()
                Text(request.method).font(.caption.monospaced()).foregroundStyle(.secondary).oneLine()
            }

            if pending.isScam {
                warning("This site is flagged as fraudulent. Do not sign.", icon: "hand.raised.fill")
            } else if pending.isSuspicious {
                warning("This site could not be verified.", icon: "questionmark.circle")
            }

            ScrollView {
                Text(message)
                    .font(.footnote.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                // Marks the end of the payload. A long one can push the line
                // that actually matters below the fold, so signing stays
                // disabled until this has been reached.
                Color.clear.frame(height: 1)
                    .onAppear { reachedEnd = true }
            }
            .frame(maxHeight: 200)
            .glassCard()

            if !reachedEnd {
                Label("Scroll to the end to read the whole request.", systemImage: "arrow.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let address = wallet.activeAddress {
                Text("Signing as \(shortAddress(address))")
                    .font(.caption).foregroundStyle(.secondary).oneLine()
            }

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
                .disabled(working || !reachedEnd)

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
                // Only leave once the dapp actually has the answer; otherwise the
                // user would believe they signed while the app received nothing.
                if await WalletConnectService.shared.respond(request, result: result) {
                    dismiss()
                } else {
                    error = String.loc("The answer could not be delivered. Try again.")
                    working = false
                }
            } catch {
                self.error = error.localizedDescription
                working = false
            }
        }
    }

    private func warning(_ text: LocalizedStringKey, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.appAccent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.appAccent.opacity(0.12), in: .rect(cornerRadius: 10))
    }

    private func shortAddress(_ a: String) -> String {
        guard a.count > 12 else { return a }
        return "\(a.prefix(8))…\(a.suffix(6))"
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
