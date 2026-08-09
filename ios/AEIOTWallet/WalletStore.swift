import Foundation
import LocalAuthentication
import Web3Core

enum WalletError: LocalizedError {
    case invalidMnemonic, invalidAddress, invalidAmount, keystoreUnavailable, approvalFailed

    var errorDescription: String? {
        switch self {
        case .invalidMnemonic: String.loc("Invalid recovery phrase. Check the 12 words and try again.")
        case .invalidAddress: String.loc("Invalid address. It should start with 0x.")
        case .invalidAmount: String.loc("Invalid amount.")
        case .keystoreUnavailable: String.loc("Wallet keys could not be loaded.")
        case .approvalFailed: String.loc("The swap was not approved on the network. Nothing was swapped.")
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
    /// Native SegWit (bc1…) receiving address — the first one, shown for receiving.
    var bitcoinAddress: String?
    /// All scanned Bitcoin addresses (receive + change). Balances must sum over
    /// these, otherwise a wallet imported from elsewhere looks emptier than it is.
    var bitcoinAddresses: [String]?
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
            let derived = await Self.deriveAddresses(from: mnemonic)
            wallets.append(WalletInfo(
                name: String.loc("Wallet \(wallets.count + 1)"),
                address: addr,
                solanaAddress: derived.solana,
                xrpAddress: derived.xrp,
                bitcoinAddress: derived.bitcoin,
                bitcoinAddresses: derived.bitcoinSet))
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

    /// Every address to check balances on. One for most networks; Bitcoin
    /// spreads funds across many, so all of them are returned.
    func addresses(for chain: Chain) -> [String] {
        if case .bitcoin = chain.kind {
            if let scanned = activeWallet?.bitcoinAddresses, !scanned.isEmpty { return scanned }
        }
        return address(for: chain).map { [$0] } ?? []
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
        guard let mnemonic = await Self.secret(for: wallet.address,
                                               prompt: String.loc("Create your addresses"))
        else { return false }
        let derived = await Self.deriveAddresses(from: mnemonic)
        guard derived.bitcoinSet != nil else { return false }
        wallets[index].solanaAddress = derived.solana
        wallets[index].xrpAddress = derived.xrp
        wallets[index].bitcoinAddress = derived.bitcoin
        wallets[index].bitcoinAddresses = derived.bitcoinSet
        persist()
        return true
    }


    /// The non-EVM addresses a seed produces.
    struct DerivedAddresses {
        var solana: String?
        var xrp: String?
        var bitcoin: String?
        var bitcoinSet: [String]?
    }

    /// Run off the main actor: turning a phrase into a seed is PBKDF2 with 2048
    /// rounds, and the Bitcoin set alone is forty key derivations. On the main
    /// actor that visibly locks the screen right after "Create Wallet".
    private static func deriveAddresses(from mnemonic: String) async -> DerivedAddresses {
        await Task.detached {
            guard let seed = BIP39.seedFromMmemonics(mnemonic) else { return DerivedAddresses() }
            return DerivedAddresses(
                solana: SolanaKey.keypair(fromSeed: seed)?.address,
                xrp: XRPKey.keypair(fromSeed: seed)?.address,
                bitcoin: BitcoinKey.keypair(fromSeed: seed)?.address,
                bitcoinSet: bitcoinAddressSet(seed: seed))
        }.value
    }

    /// Receive and change addresses within the standard gap limit. Not actor
    /// isolated: it is forty key derivations and belongs off the main thread.
    private nonisolated static func bitcoinAddressSet(seed: Data) -> [String] {
        (BitcoinKey.keypairs(fromSeed: seed) + BitcoinKey.keypairs(fromSeed: seed, change: true))
            .map(\.address)
    }

    /// Bitcoin needs every key that might hold coins, plus one for the change.
    func loadBitcoinKeys() async throws -> (keys: [BitcoinKey.Keypair], change: BitcoinKey.Keypair) {
        guard let address = activeAddress,
              let mnemonic = await Self.secret(for: address, prompt: String.loc("Authorize this transfer")),
              let seed = BIP39.seedFromMmemonics(mnemonic),
              let change = BitcoinKey.changeKeypair(fromSeed: seed) else {
            throw WalletError.keystoreUnavailable
        }
        let keys = BitcoinKey.keypairs(fromSeed: seed) + BitcoinKey.keypairs(fromSeed: seed, change: true)
        return (keys, change)
    }

    /// Bitcoin needs both the spending key and the change key.
    func loadBitcoinKeypairs() async throws -> (spend: BitcoinKey.Keypair, change: BitcoinKey.Keypair) {
        guard let address = activeAddress,
              let mnemonic = await Self.secret(for: address, prompt: String.loc("Authorize this transfer")),
              let seed = BIP39.seedFromMmemonics(mnemonic),
              let spend = BitcoinKey.keypair(fromSeed: seed),
              let change = BitcoinKey.changeKeypair(fromSeed: seed) else {
            throw WalletError.keystoreUnavailable
        }
        return (spend, change)
    }

    func loadXRPKeypair() async throws -> XRPKey.Keypair {
        guard let address = activeAddress,
              let mnemonic = await Self.secret(for: address, prompt: String.loc("Authorize this transfer")),
              let seed = BIP39.seedFromMmemonics(mnemonic),
              let keypair = XRPKey.keypair(fromSeed: seed) else {
            throw WalletError.keystoreUnavailable
        }
        return keypair
    }

    func loadSolanaKeypair() async throws -> SolanaKey.Keypair {
        guard let address = activeAddress,
              let mnemonic = await Self.secret(for: address, prompt: String.loc("Authorize this transfer")),
              let seed = BIP39.seedFromMmemonics(mnemonic),
              let keypair = SolanaKey.keypair(fromSeed: seed) else {
            throw WalletError.keystoreUnavailable
        }
        return keypair
    }

    /// The 12-word phrase for a wallet, for the export screen. Guard the call site with Face ID.
    func mnemonic(for wallet: WalletInfo) async -> String? {
        await Self.secret(for: wallet.address, prompt: String.loc("Reveal your recovery phrase"))
    }

    /// Reads a seed phrase off the main actor. A keychain item behind Face ID
    /// blocks its thread until the prompt is answered, and on the main actor
    /// that freezes the interface — long enough and iOS kills the app outright,
    /// which could happen mid-send.
    private static func secret(for address: String, prompt: String) async -> String? {
        await Task.detached {
            Keychain.load(key: "wallet.mnemonic.\(address)", prompt: prompt)
        }.value
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

    /// The reason is what the system biometric prompt shows. It defaults to the
    /// transfer wording because most callers send coins, but a dapp signature is
    /// not a transfer and must not claim to be one.
    func loadKeystore(reason: String = String.loc("Authorize this transfer")) async throws -> BIP32Keystore {
        guard let address = activeAddress,
              let mnemonic = await Self.secret(for: address, prompt: reason) else {
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
