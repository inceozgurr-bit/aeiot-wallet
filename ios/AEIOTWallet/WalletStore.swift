import Foundation
import LocalAuthentication
import Web3Core

enum WalletError: LocalizedError {
    case invalidMnemonic, invalidAddress, invalidAmount, keystoreUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidMnemonic: String.loc("Invalid recovery phrase. Check the 12 words and try again.")
        case .invalidAddress: String.loc("Invalid address. It should start with 0x.")
        case .invalidAmount: String.loc("Invalid amount.")
        case .keystoreUnavailable: String.loc("Wallet keys could not be loaded.")
        }
    }
}

struct WalletInfo: Codable, Identifiable, Hashable {
    var name: String
    /// The 0x… address, shared by every EVM network.
    let address: String
    /// Derived from the same phrase on the ed25519 curve. Optional because
    /// wallets created before Solana support was added do not have it yet.
    var solanaAddress: String?
    /// Same phrase, XRP's own derivation path and address format.
    var xrpAddress: String?
    /// Native SegWit (bc1…) receiving address.
    var bitcoinAddress: String?
    var id: String { address }
}

@Observable @MainActor
final class WalletStore {
    private(set) var wallets: [WalletInfo] = []
    private(set) var activeAddress: String?
    var isLocked = false

    var address: String? { activeAddress }
    var activeWallet: WalletInfo? { wallets.first { $0.address == activeAddress } }

    // Wallet list lives in the Keychain (not UserDefaults) so it survives
    // app deletion — reinstalling on the same device restores all wallets.
    private static let walletsKey = "wallet.list"
    private static let activeKey = "wallet.active"

    init() {
        if let json = Keychain.load(key: Self.walletsKey),
           let decoded = try? JSONDecoder().decode([WalletInfo].self, from: Data(json.utf8)) {
            wallets = decoded
        }
        activeAddress = Keychain.load(key: Self.activeKey) ?? wallets.first?.address
        isLocked = !wallets.isEmpty && Self.biometricUnlockEnabled
    }

    /// The Settings toggle, defaulting to on when the user has never changed it.
    private static var biometricUnlockEnabled: Bool {
        UserDefaults.standard.object(forKey: "requireBiometricUnlock") as? Bool ?? true
    }

    /// Generates a new phrase but does NOT activate the wallet yet —
    /// the user must confirm they backed it up first (confirmBackup).
    func createWallet() throws -> String {
        guard let mnemonic = try BIP39.generateMnemonics(bitsOfEntropy: 128) else {
            throw WalletError.invalidMnemonic
        }
        return mnemonic
    }

    func confirmBackup(mnemonic: String) async throws {
        try await add(mnemonic: mnemonic)
    }

    func importWallet(mnemonic: String) async throws {
        let cleaned = mnemonic
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        try await add(mnemonic: cleaned)
    }

    private func add(mnemonic: String) async throws {
        let keystore = try await Task.detached {
            try BIP32Keystore(mnemonics: mnemonic, password: "")
        }.value
        guard let addr = keystore?.addresses?.first?.address else { throw WalletError.invalidMnemonic }
        guard Keychain.save(mnemonic, key: "wallet.mnemonic.\(addr)", requireBiometry: true) else {
            throw WalletError.keystoreUnavailable
        }
        if !wallets.contains(where: { $0.address == addr }) {
            let seed = BIP39.seedFromMmemonics(mnemonic)
            wallets.append(WalletInfo(
                name: String.loc("Wallet \(wallets.count + 1)"),
                address: addr,
                solanaAddress: seed.flatMap(SolanaKey.keypair(fromSeed:))?.address,
                xrpAddress: seed.flatMap(XRPKey.keypair(fromSeed:))?.address,
                bitcoinAddress: seed.flatMap(BitcoinKey.keypair(fromSeed:))?.address))
        }
        activeAddress = addr
        persist()
    }

    func select(_ wallet: WalletInfo) {
        activeAddress = wallet.address
        persist()
    }

    func rename(_ wallet: WalletInfo, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = wallets.firstIndex(where: { $0.id == wallet.id }) else { return }
        wallets[idx].name = trimmed
        persist()
    }

    func remove(_ wallet: WalletInfo) {
        Keychain.delete(key: "wallet.mnemonic.\(wallet.address)")
        wallets.removeAll { $0.id == wallet.id }
        if activeAddress == wallet.address { activeAddress = wallets.first?.address }
        if wallets.isEmpty { isLocked = false }
        persist()
    }

    /// Which address this network uses. Every EVM chain shares the 0x… one;
    /// Solana has its own.
    func address(for chain: Chain) -> String? {
        switch chain.kind {
        case .evm: activeAddress
        case .solana: activeWallet?.solanaAddress
        case .xrp: activeWallet?.xrpAddress
        case .bitcoin: activeWallet?.bitcoinAddress
        }
    }

    /// Wallets made before Solana and XRP support have no address for those
    /// networks. Deriving them needs the seed, so this asks for biometrics —
    /// once, then both addresses are stored.
    @discardableResult
    func backfillAddresses() async -> Bool {
        guard let wallet = activeWallet,
              let index = wallets.firstIndex(where: { $0.id == wallet.id }) else { return false }
        if wallet.solanaAddress != nil && wallet.xrpAddress != nil
            && wallet.bitcoinAddress != nil { return true }
        guard let mnemonic = Keychain.load(key: "wallet.mnemonic.\(wallet.address)",
                                           prompt: String.loc("Create your addresses")),
              let seed = BIP39.seedFromMmemonics(mnemonic) else { return false }
        wallets[index].solanaAddress = SolanaKey.keypair(fromSeed: seed)?.address
        wallets[index].xrpAddress = XRPKey.keypair(fromSeed: seed)?.address
        wallets[index].bitcoinAddress = BitcoinKey.keypair(fromSeed: seed)?.address
        persist()
        return true
    }

    /// Bitcoin needs both the spending key and the change key.
    func loadBitcoinKeypairs() async throws -> (spend: BitcoinKey.Keypair, change: BitcoinKey.Keypair) {
        guard let address = activeAddress,
              let mnemonic = Keychain.load(key: "wallet.mnemonic.\(address)",
                                           prompt: String.loc("Authorize this transfer")),
              let seed = BIP39.seedFromMmemonics(mnemonic),
              let spend = BitcoinKey.keypair(fromSeed: seed),
              let change = BitcoinKey.changeKeypair(fromSeed: seed) else {
            throw WalletError.keystoreUnavailable
        }
        return (spend, change)
    }

    func loadXRPKeypair() async throws -> XRPKey.Keypair {
        guard let address = activeAddress,
              let mnemonic = Keychain.load(key: "wallet.mnemonic.\(address)",
                                           prompt: String.loc("Authorize this transfer")),
              let seed = BIP39.seedFromMmemonics(mnemonic),
              let keypair = XRPKey.keypair(fromSeed: seed) else {
            throw WalletError.keystoreUnavailable
        }
        return keypair
    }

    func loadSolanaKeypair() async throws -> SolanaKey.Keypair {
        guard let address = activeAddress,
              let mnemonic = Keychain.load(key: "wallet.mnemonic.\(address)",
                                           prompt: String.loc("Authorize this transfer")),
              let seed = BIP39.seedFromMmemonics(mnemonic),
              let keypair = SolanaKey.keypair(fromSeed: seed) else {
            throw WalletError.keystoreUnavailable
        }
        return keypair
    }

    /// The 12-word phrase for a wallet, for the export screen. Guard the call site with Face ID.
    func mnemonic(for wallet: WalletInfo) -> String? {
        Keychain.load(key: "wallet.mnemonic.\(wallet.address)",
                      prompt: String.loc("Reveal your recovery phrase"))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(wallets),
           let json = String(data: data, encoding: .utf8) {
            Keychain.save(json, key: Self.walletsKey)
        }
        if let activeAddress {
            Keychain.save(activeAddress, key: Self.activeKey)
        }
    }

    func loadKeystore() async throws -> BIP32Keystore {
        guard let address = activeAddress,
              let mnemonic = Keychain.load(key: "wallet.mnemonic.\(address)",
                                           prompt: String.loc("Authorize this transfer")) else {
            throw WalletError.keystoreUnavailable
        }
        guard let keystore = try await Task.detached(operation: {
            try BIP32Keystore(mnemonics: mnemonic, password: "")
        }).value else { throw WalletError.keystoreUnavailable }
        return keystore
    }

    func unlock() async {
        if await authenticate(reason: String.loc("Unlock your wallet")) {
            isLocked = false
        }
    }

    /// Face ID / passcode gate. On a real device with no passcode set this must
    /// FAIL CLOSED — an unprotected phone must not silently unlock the wallet.
    func authenticate(reason: String) async -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
        #endif
    }
}
