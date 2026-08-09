import SwiftUI
import Web3Core

struct SendView: View {
    @Environment(WalletStore.self) private var wallet
    @Environment(AddressBook.self) private var addressBook
    @Environment(\.dismiss) private var dismiss
    var onSent: () -> Void

    @State private var token = Token.aeiot
    @State private var recipient = ""
    @State private var amount = ""
    @State private var showScanner = false
    @State private var isSending = false
    @State private var txHash: String?
    @State private var confirmed = false
    @State private var sentAmount = ""
    @State private var errorMessage: String?
    @State private var showSaveContact = false
    @State private var newContactName = ""
    @State private var showConfirm = false
    @State private var estimatedFee: Decimal?

    /// Digits normalized for parsing: Turkish keyboards produce "," as the decimal separator.
    private var normalizedAmount: String {
        amount.replacingOccurrences(of: ",", with: ".")
    }

    /// The EIP-55 checksummed address, or nil if the recipient is not a valid address.
    private var checksummedRecipient: String? {
        EthereumAddress(recipient)?.address
    }

    private var isSolana: Bool {
        if case .solana = token.chain.kind { return true }
        return false
    }

    private var isXRP: Bool {
        if case .xrp = token.chain.kind { return true }
        return false
    }

    private var isBitcoin: Bool {
        if case .bitcoin = token.chain.kind { return true }
        return false
    }

    /// Every network writes addresses differently: 0x… hex, Solana base58, XRP r….
    private var isRecipientValid: Bool {
        switch token.chain.kind {
        case .evm: checksummedRecipient != nil
        case .solana: Base58.decode(recipient)?.count == 32
        case .xrp: XRPKey.isValidAddress(recipient)
        case .bitcoin: BitcoinKey.isValidAddress(recipient)
        }
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            if let txHash {
                sentView(txHash)
            } else {
                form
            }
        }
        .navigationTitle("Send")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSaveContact) { saveContactSheet }
    }

    private var isNewAddress: Bool {
        recipient.hasPrefix("0x") && recipient.count == 42 &&
        !addressBook.contacts.contains { $0.address.lowercased() == recipient.lowercased() }
    }

    private var saveContactSheet: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. Ahmet)", text: $newContactName)
                Text(recipient).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .navigationTitle("Save Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        addressBook.add(name: newContactName, address: recipient)
                        newContactName = ""
                        showSaveContact = false
                    }
                    .disabled(newContactName.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSaveContact = false }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var form: some View {
        VStack(spacing: 18) {
            // 20 coins across 6 networks: a grouped menu, not a segmented picker.
            Menu {
                ForEach(Chain.all) { chain in
                    Section(chain.name) {
                        ForEach(Token.all.filter { $0.chain == chain }) { option in
                            Button {
                                Haptic.tap()
                                token = option
                            } label: {
                                Text(option.symbol)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    TokenLogo(token: token, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(token.symbol).font(.headline)
                        Text(token.chain.name).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                .contentShape(.rect)
            }
            .tint(.primary)

            HStack {
                TextField("Recipient address (0x…)", text: $recipient)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.callout.monospaced())
                if !addressBook.contacts.isEmpty {
                    Menu {
                        ForEach(addressBook.contacts) { contact in
                            Button(contact.name) { recipient = contact.address }
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
                Button {
                    Haptic.tap()
                    if let pasted = UIPasteboard.general.string { recipient = pasted }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                Button {
                    Haptic.tap()
                    showScanner = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
            }
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 14))

            if isNewAddress {
                Button {
                    Haptic.tap()
                    showSaveContact = true
                } label: {
                    Label("Save to Address Book", systemImage: "person.badge.plus")
                        .font(.footnote)
                }
            }

            TextField("Amount", text: $amount)
                .keyboardType(.decimalPad)
                .font(.title2.monospacedDigit())
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 14))

            Text("Network fee is paid in \(token.chain.nativeSymbol) on \(token.chain.name).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                Haptic.tap()
                prepareConfirm()
            } label: {
                Text(isSending ? String.loc("Sending…") : String.loc("Review \(token.symbol) Transfer"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .disabled(isSending || recipient.isEmpty || amount.isEmpty)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Color.appAccent)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .sheet(isPresented: $showScanner) {
            QRScannerView { scanned in
                recipient = scanned.replacingOccurrences(of: "ethereum:", with: "")
                showScanner = false
            }
        }
        .sheet(isPresented: $showConfirm) { confirmSheet }
    }

    private var confirmSheet: some View {
        VStack(spacing: 18) {
            Text("Confirm Transfer").font(.title2.bold())

            VStack(spacing: 14) {
                confirmRow("Amount", "\(normalizedAmount) \(token.symbol)")
                Divider()
                // Sending on the wrong network loses the coins, so name it here.
                confirmRow("Network", token.chain.name)
                Divider()
                // A fee spike, or a hostile fee estimate, should be visible
                // before signing rather than discovered afterwards.
                confirmRow("Network fee", estimatedFee.map {
                    "≈ \($0.formatted(.number.precision(.fractionLength(0...8)))) \(token.chain.nativeSymbol)"
                } ?? "—")
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("To").foregroundStyle(.secondary).font(.subheadline)
                    Text(checksummedRecipient ?? recipient)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    if let match = matchedContactName {
                        Text(match).font(.caption).foregroundStyle(.tint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 16))

            Label("Check the address carefully. Transfers on the blockchain cannot be reversed.",
                  systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                Haptic.tap()
                showConfirm = false
                performSend()
            } label: {
                Text("Confirm & Send")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
        // Asked for when the sheet opens, so the number is the current one.
        .task(id: token.id) { estimatedFee = await ChainService.shared.estimatedFee(for: token) }
    }

    private func confirmRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).oneLine()
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }

    private var matchedContactName: String? {
        addressBook.contacts.first { $0.address.lowercased() == recipient.lowercased() }?.name
    }

    private func sentView(_ hash: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            if confirmed {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.appAccent)
                    .transition(.scale.combined(with: .opacity))
                Text("Transfer Confirmed").font(.title2.bold())
                Text("\(sentAmount) \(token.symbol) delivered")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.large)
                Text("Sent — waiting for confirmation…")
                    .font(.headline)
                Text("This usually takes a few seconds on Base.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let url = token.chain.transactionURL(hash) {
                Link("View in Explorer", destination: url).font(.footnote)
            }
            Spacer()
            Button {
                onSent()
                dismiss()
            } label: {
                Text("Back to Home")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(24)
        .animation(.bouncy, value: confirmed)
    }

    private func prepareConfirm() {
        errorMessage = nil
        guard isRecipientValid else {
            errorMessage = isSolana
                ? String.loc("Invalid Solana address.")
                : String.loc("Invalid address. It should start with 0x.")
            return
        }
        guard let value = Decimal(string: normalizedAmount), value > 0 else {
            errorMessage = String.loc("Invalid amount.")
            return
        }
        showConfirm = true
    }

    /// Polls the right network until the transfer lands. Never throws: a timeout
    /// just leaves the screen on "sent, waiting" rather than claiming failure.
    private func waitForConfirmation(_ hash: String) async throws -> Bool {
        // Bitcoin blocks take ~10 minutes, so waiting in the UI is pointless:
        // the screen already shows "sent" with a link to the explorer.
        if isBitcoin { return false }
        if isSolana || isXRP {
            for _ in 0..<15 {
                let done = isXRP
                    ? (try? await XRPService.isConfirmed(hash: hash)) == true
                    : (try? await SolanaService.isConfirmed(signature: hash)) == true
                if done { return true }
                try? await Task.sleep(for: .seconds(2))
            }
            return false
        }
        return (try? await ChainService.shared.waitForConfirmation(hash: hash, on: token.chain)) == true
    }

    private func performSend() {
        isSending = true
        errorMessage = nil
        sentAmount = normalizedAmount
        Task {
            do {
                // Reading the seed triggers the device biometric/passcode check (Keychain ACL).
                let hash: String
                if isBitcoin {
                    let keys = try await wallet.loadBitcoinKeys()
                    hash = try await BitcoinService.send(
                        keys: keys.keys, change: keys.change, to: recipient,
                        amount: Decimal(string: normalizedAmount) ?? 0)
                } else if isXRP {
                    let keypair = try await wallet.loadXRPKeypair()
                    hash = try await XRPService.send(
                        from: keypair, to: recipient, amount: Decimal(string: normalizedAmount) ?? 0)
                } else if isSolana {
                    let keypair = try await wallet.loadSolanaKeypair()
                    let value = Decimal(string: normalizedAmount) ?? 0
                    if let mint = token.contract {
                        hash = try await SolanaService.sendToken(
                            from: keypair, to: recipient, mint: mint, amount: value,
                            decimals: token.decimals, symbol: token.symbol)
                    } else {
                        hash = try await SolanaService.sendSOL(from: keypair, to: recipient, amount: value)
                    }
                } else {
                    let keystore = try await wallet.loadKeystore()
                    hash = try await ChainService.shared.send(
                        token: token, to: recipient, amount: normalizedAmount, keystore: keystore)
                }
                txHash = hash
                isSending = false
                if try await waitForConfirmation(hash) {
                    confirmed = true
                    Haptic.tap()
                    try? await Task.sleep(for: .seconds(2))
                    onSent()
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
                isSending = false
            }
        }
    }
}
