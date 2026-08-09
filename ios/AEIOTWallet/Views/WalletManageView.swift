import SwiftUI

struct WalletManageView: View {
    @Environment(WalletStore.self) private var wallet
    @Environment(\.dismiss) private var dismiss

    @State private var toDelete: WalletInfo?
    @State private var toExport: WalletInfo?
    @State private var toRename: WalletInfo?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(wallet.wallets) { info in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.name).font(.headline).oneLine()
                            Text(shortAddress(info.address))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Haptic.tap()
                            renameText = info.name
                            toRename = info
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        Button {
                            Haptic.tap()
                            toExport = info
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderless)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            toDelete = info
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Manage Wallets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Delete Wallet?", isPresented: .init(
                get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
                Button("Delete", role: .destructive) {
                    if let toDelete { wallet.remove(toDelete) }
                    toDelete = nil
                    if wallet.wallets.isEmpty { dismiss() }
                }
                Button("Cancel", role: .cancel) { toDelete = nil }
            } message: {
                Text("This removes the wallet from this device. You can only restore it with its 12-word recovery phrase.")
            }
            .alert("Rename Wallet", isPresented: .init(
                get: { toRename != nil }, set: { if !$0 { toRename = nil } })) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let toRename { wallet.rename(toRename, to: renameText) }
                    toRename = nil
                }
                Button("Cancel", role: .cancel) { toRename = nil }
            }
            .sheet(item: $toExport) { WalletExportView(wallet: $0) }
        }
    }

    private func shortAddress(_ a: String) -> String {
        guard a.count > 12 else { return a }
        return "\(a.prefix(8))…\(a.suffix(6))"
    }
}

struct WalletExportView: View {
    @Environment(WalletStore.self) private var walletStore
    let wallet: WalletInfo

    @State private var phrase: String?
    @State private var revealed = false
    @State private var copied = false

    private var copyKey: LocalizedStringKey { copied ? "Copied" : "Copy" }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Export \(wallet.name)").font(.title3.bold())
            Text(wallet.address)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Label("Never share these 12 words. Anyone who has them controls this wallet.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Color.appAccent)
                .multilineTextAlignment(.center)

            if revealed, let phrase {
                let words = phrase.split(separator: " ").map(String.init)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                        HStack(spacing: 4) {
                            Text("\(i + 1).").foregroundStyle(.tertiary).font(.caption2)
                            Text(w).font(.callout.monospaced())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .glassEffect(.regular, in: .rect(cornerRadius: 8))
                    }
                }
                HStack(spacing: 20) {
                    Button {
                        Haptic.tap()
                        SecurePasteboard.copy(phrase)
                        copied = true
                    } label: {
                        Label(copyKey, systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline).oneLine()
                    }
                    if let pdf = pdfURL(phrase: phrase) {
                        ShareLink(item: pdf) {
                            Label("Export PDF", systemImage: "square.and.arrow.up")
                                .font(.subheadline).oneLine()
                        }
                    }
                }
            } else {
                Button {
                    Haptic.tap()
                    reveal()
                } label: {
                    Label(String.loc("Reveal with \(Biometrics.label)"), systemImage: "lock.open")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
            }
            Spacer()
        }
        .padding(24)
        .padding(.top, 20)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
    }

    private func reveal() {
        Task {
            guard await walletStore.authenticate(reason: String.loc("Reveal your recovery phrase")) else { return }
            phrase = walletStore.mnemonic(for: wallet)
            revealed = phrase != nil
        }
    }

    /// Renders a one-page recovery sheet PDF to a temp file and returns its URL.
    private func pdfURL(phrase: String) -> URL? {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 @72dpi
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AEIOT-\(wallet.name).pdf")
        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                var y: CGFloat = 56
                func draw(_ text: String, _ font: UIFont, _ color: UIColor = .black) {
                    (text as NSString).draw(at: CGPoint(x: 48, y: y),
                        withAttributes: [.font: font, .foregroundColor: color])
                    y += font.lineHeight + 8
                }
                draw(String.loc("AEIOT Wallet — Recovery Sheet"), .boldSystemFont(ofSize: 22))
                draw(wallet.name, .systemFont(ofSize: 15), .darkGray)
                draw(wallet.address, .monospacedSystemFont(ofSize: 10, weight: .regular), .gray)
                y += 12
                draw(String.loc("Recovery phrase (12 words):"), .boldSystemFont(ofSize: 14))
                let words = phrase.split(separator: " ").enumerated()
                    .map { "\($0.offset + 1). \($0.element)" }
                for line in stride(from: 0, to: words.count, by: 3) {
                    draw(words[line..<min(line + 3, words.count)].joined(separator: "     "),
                         .monospacedSystemFont(ofSize: 13, weight: .medium))
                }
                y += 12
                draw("AEIOT: \(Token.aeiot.contract ?? "")",
                     .monospacedSystemFont(ofSize: 9, weight: .regular), .gray)
                draw(String.loc("Network: Base (chainId 8453)"), .systemFont(ofSize: 11), .gray)
                y += 16
                // draw(in:) rather than draw(at:) so the translated warning wraps itself.
                let warning = String.loc("⚠︎ Keep this sheet secret and offline. Anyone with these 12 words controls this wallet. There is no reset.")
                (warning as NSString).draw(
                    in: CGRect(x: 48, y: y, width: page.width - 96, height: 60),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 11),
                                     .foregroundColor: UIColor(Color.appAccent)])
            }
            return url
        } catch { return nil }
    }
}
