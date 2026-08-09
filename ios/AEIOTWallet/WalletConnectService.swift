import Combine
import CryptoSwift
import Foundation
import ReownWalletKit
import web3swift
import Web3Core

/// Connects this wallet to dapps over WalletConnect. The app is always the
/// wallet side: a dapp shows a `wc:` code, we pair, it asks for signatures, and
/// every one of those goes through the same Face ID gate as sending coins.
@Observable @MainActor
final class WalletConnectService {
    static let shared = WalletConnectService()

    /// Sessions currently approved.
    private(set) var sessions: [Session] = []
    /// A dapp asking to connect; the UI shows a sheet while this is set.
    var proposal: Pending<Session.Proposal>?
    /// A dapp asking for a signature.
    var request: Pending<Request>?

    /// Whatever the dapp sent, carried together with the relay's own verdict on
    /// the origin that sent it. Keeping them in one value means the screen can
    /// never show one request's text above another request's provenance.
    struct Pending<Body> {
        let body: Body
        let verified: VerifyContext?

        /// The relay could not vouch for this origin, or actively flagged it.
        var isSuspicious: Bool {
            guard let validation = verified?.validation else { return true }
            return validation != .valid
        }

        var isScam: Bool { verified?.validation == .scam }
    }
    /// Surfaced to the user when a pairing or response fails.
    var failure: String?

    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private init() {}

    /// Safe to call more than once; only the first call configures the SDK.
    func start() {
        // The redirect only throws for link mode, which needs a universal link;
        // QR pairing does not, so this cannot fail in practice.
        guard !started,
              let projectID = Bundle.main.object(forInfoDictionaryKey: "ReownProjectID") as? String,
              !projectID.isEmpty,
              let redirect = try? AppMetadata.Redirect(native: "aeiot://", universal: nil)
        else { return }
        started = true

        Networking.configure(groupIdentifier: Self.appGroup,
                             projectId: projectID,
                             socketFactory: RelaySocketFactory())
        WalletKit.configure(
            metadata: AppMetadata(
                name: "AEIOT",
                description: String.loc("Your keys, your coins. Stored only on this device."),
                url: "https://aeiot.app",
                icons: [],
                redirect: redirect
            ),
            crypto: WalletCrypto()
        )

        // The second value is the relay's origin verification — the SDK's own
        // phishing defence. Dropping it is how a wallet ends up showing a
        // flagged site exactly like a legitimate one.
        WalletKit.instance.sessionProposalPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] proposal, context in
                self?.proposal = Pending(body: proposal, verified: context)
            }
            .store(in: &cancellables)

        WalletKit.instance.sessionRequestPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request, context in
                self?.request = Pending(body: request, verified: context)
            }
            .store(in: &cancellables)

        WalletKit.instance.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in self?.sessions = sessions }
            .store(in: &cancellables)

        sessions = WalletKit.instance.getSessions()
    }

    /// A scanned QR code or an `aeiot://` deep link. Anything that is not a
    /// pairing URI is ignored rather than reported, since the same scanner also
    /// reads plain recipient addresses.
    func pair(_ scanned: String) async {
        // A scanned code is a bare `wc:` URI, but a deep link arrives wrapped as
        // `aeiot://wc?uri=…`. The plain parser rejects the wrapped form, so
        // links from a dapp used to be swallowed in silence.
        let uri = WalletConnectURI(string: scanned)
            ?? URL(string: scanned).flatMap { try? WalletConnectURI(deeplinkUri: $0) }
        guard let uri else { return }
        do {
            try await WalletKit.instance.pair(uri: uri)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// An approval that fails leaves the dapp waiting forever unless it is told,
    /// so a failure here is turned into an explicit rejection.
    func approve(_ proposal: Session.Proposal, address: String) async {
        do {
            let namespaces = try AutoNamespaces.build(
                sessionProposal: proposal,
                chains: Self.requestedChains(in: proposal),
                // Our own list, not the dapp's: handing back what it asked for
                // advertised support for eth_sign and wallet_addEthereumChain,
                // the very methods this wallet refuses.
                methods: Self.supportedMethods,
                events: Array(proposal.requiredNamespaces.values.flatMap(\.events)),
                accounts: Self.requestedChains(in: proposal).compactMap {
                    Account(blockchain: $0, address: address)
                }
            )
            _ = try await WalletKit.instance.approve(proposalId: proposal.id, namespaces: namespaces)
        } catch {
            failure = error.localizedDescription
            try? await WalletKit.instance.rejectSession(proposalId: proposal.id, reason: .userRejected)
        }
        self.proposal = nil
    }

    func reject(_ proposal: Session.Proposal) async {
        try? await WalletKit.instance.rejectSession(proposalId: proposal.id, reason: .userRejected)
        self.proposal = nil
    }

    func disconnect(_ session: Session) async {
        do {
            try await WalletKit.instance.disconnect(topic: session.topic)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Answers a signing request with a result the dapp can use. Returns false
    /// if the answer never reached the relay: the signature exists but the dapp
    /// did not get it, so the sheet must stay up rather than imply success.
    @discardableResult
    func respond(_ request: Request, result: String) async -> Bool {
        do {
            try await WalletKit.instance.respond(topic: request.topic,
                                                 requestId: request.id,
                                                 response: .response(AnyCodable(result)))
            self.request = nil
            return true
        } catch {
            failure = error.localizedDescription
            return false
        }
    }

    /// Turns the dapp down. Also used for the methods we deliberately refuse.
    /// The request is cleared either way — a rejection the user already made
    /// should not come back — but a delivery failure is surfaced.
    func decline(_ request: Request, reason: String = "User rejected") async {
        do {
            try await WalletKit.instance.respond(
                topic: request.topic,
                requestId: request.id,
                response: .error(JSONRPCError(code: 4001, message: reason)))
        } catch {
            failure = error.localizedDescription
        }
        self.request = nil
    }

    /// Methods a dapp may ask for. `eth_sign` is missing on purpose: it signs an
    /// opaque hash with no context shown to the user, and modern dapps do not
    /// need it. `wallet_addEthereumChain` is refused too — taking an RPC URL
    /// from a dapp would let it decide what this wallet talks to.
    static let supportedMethods = ["personal_sign", "eth_signTypedData", "eth_signTypedData_v4"]

    /// Produces the dapp's answer. The keystore is loaded per request, which is
    /// what forces a fresh Face ID prompt every single time — an approved
    /// session is permission to ask, never permission to sign.
    func sign(_ request: Request, using wallet: WalletStore) async throws -> String {
        // Checked before the keystore is touched: asking for Face ID and only
        // then refusing trains the user to approve prompts the wallet cannot
        // honour anyway.
        guard Self.supportedMethods.contains(request.method) else {
            throw WalletConnectError.unsupportedMethod(request.method)
        }
        // The dapp names the account it expects to sign with. If the user
        // switched wallets after connecting, signing with the current one hands
        // back a signature from a key the dapp never asked for.
        try requireExpectedAccount(request, active: wallet.activeAddress)
        let keystore = try await wallet.loadKeystore(reason: String.loc("Sign this request"))
        guard let address = keystore.addresses?.first else { throw WalletError.keystoreUnavailable }

        switch request.method {
        case "personal_sign":
            let params = try request.params.get([String].self)
            guard let raw = params.first else { throw WalletConnectError.malformedRequest }
            let message = Data.fromHex(raw) ?? Data(raw.utf8)
            guard let signature = try Web3Signer.signPersonalMessage(
                message, keystore: keystore, account: address, password: "")
            else { throw WalletConnectError.signingFailed }
            return Self.hex(signature)

        case "eth_signTypedData", "eth_signTypedData_v4":
            let params = try request.params.get([String].self)
            // The dapp sends [address, json] — the JSON is the second entry.
            guard let json = params.last else { throw WalletConnectError.malformedRequest }
            let payload = try EIP712Parser.parse(json)
            let signature = try Web3Signer.signEIP712(
                payload, keystore: keystore, account: address, password: "")
            return Self.hex(signature)

        default:
            throw WalletConnectError.unsupportedMethod(request.method)
        }
    }

    /// The address a request is meant for: `personal_sign` puts it second,
    /// typed data first. Anything that is not a 0x address is ignored, so a dapp
    /// that omits it is not blocked — only a genuine mismatch is.
    private func requireExpectedAccount(_ request: Request, active: String?) throws {
        guard let params = try? request.params.get([String].self),
              let expected = params.first(where: { $0.hasPrefix("0x") && $0.count == 42 })
        else { return }
        guard let active, expected.lowercased() == active.lowercased() else {
            throw WalletConnectError.wrongAccount
        }
    }

    /// Both CryptoSwift and web3swift define `toHexString()`, so spelling it out
    /// avoids an ambiguous call.
    private static func hex(_ data: Data) -> String {
        "0x" + data.map { String(format: "%02x", $0) }.joined()
    }

    /// What the confirmation sheet shows before the user approves. Nothing here
    /// is trusted: it is the dapp's own text, flattened to something a person
    /// can actually read, with control characters made visible so a payload
    /// cannot reorder or hide itself on screen.
    static func readableMessage(for request: Request) -> String {
        switch request.method {
        case "personal_sign":
            guard let params = try? request.params.get([String].self), let raw = params.first
            else { return request.method }
            if let data = Data.fromHex(raw), let text = String(data: data, encoding: .utf8) {
                return sanitized(text)
            }
            // Not readable text: an opaque digest. Say so rather than showing
            // hex that means nothing to the person approving it.
            return String.loc("This app is asking you to sign data this wallet cannot read.")
        case "eth_signTypedData", "eth_signTypedData_v4":
            guard let json = (try? request.params.get([String].self))?.last else { return request.method }
            return sanitized(typedDataSummary(json) ?? json)
        default:
            return request.method
        }
    }

    /// Pulls the parts of an EIP-712 payload that decide what is being agreed
    /// to, so a permit does not arrive disguised as a wall of JSON.
    private static func typedDataSummary(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        var lines: [String] = []
        if let primaryType = root["primaryType"] as? String {
            lines.append("\(String.loc("Type")): \(primaryType)")
        }
        if let domain = root["domain"] as? [String: Any] {
            if let name = domain["name"] as? String { lines.append("\(String.loc("Site")): \(name)") }
            if let contract = domain["verifyingContract"] as? String {
                lines.append("\(String.loc("Contract")): \(contract)")
            }
            if let chain = domain["chainId"] {
                let id = (chain as? NSNumber)?.stringValue ?? "\(chain)"
                let known = Chain.all.first { chain in
                    guard case let .evm(chainID) = chain.kind else { return false }
                    return String(chainID) == id
                }
                lines.append("\(String.loc("Network")): \(known?.name ?? id)")
            }
        }
        if let message = root["message"] as? [String: Any] {
            // Spender and amount are what a drain actually needs; surface them
            // above the rest of the payload whenever the dapp includes them.
            for key in ["spender", "to", "value", "amount", "deadline"] where message[key] != nil {
                lines.append("\(key): \(message[key]!)")
            }
        }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n") + "\n\n" + json
    }

    /// Bidirectional overrides and zero-width characters can make a payload read
    /// as something other than what gets signed.
    private static func sanitized(_ text: String) -> String {
        let hostile = Set<Character>("\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}\u{200B}\u{200C}\u{200D}\u{FEFF}")
        return String(text.map { hostile.contains($0) ? "\u{FFFD}" : $0 })
    }

    /// The connected app a request belongs to, so the signing sheet can name it.
    func dappName(for request: Request) -> String {
        sessions.first { $0.topic == request.topic }?.peer.name ?? String.loc("Unknown app")
    }

    /// Only the chains this wallet actually holds keys for, so a proposal asking
    /// for anything else is narrowed down rather than approved wholesale.
    private static func requestedChains(in proposal: Session.Proposal) -> [Blockchain] {
        let supported = Set(Chain.all.compactMap { chain -> String? in
            guard case let .evm(chainID) = chain.kind else { return nil }
            return "eip155:\(chainID)"
        })
        let asked = proposal.requiredNamespaces.values.compactMap(\.chains).flatMap { $0 }
            + (proposal.optionalNamespaces?.values.compactMap(\.chains).flatMap { $0 } ?? [])
        return asked.filter { supported.contains($0.absoluteString) }
    }

    /// Must match the App Groups entitlement — the SDK stores its own keys in it.
    private static let appGroup = "group.aeiot.app001"
}

/// The relay connection. Reown ships no socket of its own; its sample app pulls
/// in Starscream, which URLSession's own web socket makes unnecessary here.
private struct RelaySocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting { RelaySocket(url: url) }
}

private final class RelaySocket: NSObject, WebSocketConnecting, URLSessionWebSocketDelegate {
    var isConnected = false
    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onText: ((String) -> Void)?
    var request: URLRequest

    private var task: URLSessionWebSocketTask?
    /// Recreated after each disconnect, since invalidating is what releases the
    /// session's strong reference to this delegate.
    private var session: URLSession?

    private var liveSession: URLSession {
        if let session { return session }
        let created = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        session = created
        return created
    }

    init(url: URL) {
        request = URLRequest(url: url)
        super.init()
    }

    func connect() {
        // The relay retries by calling connect() again; without dropping the old
        // task it stays alive alongside the new one and both keep reading.
        task?.cancel(with: .goingAway, reason: nil)
        task = liveSession.webSocketTask(with: request)
        task?.resume()
        receiveNext()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
        // URLSession holds its delegate — this object — until invalidated, so
        // without this the socket and its connection pool live until the app
        // exits. A fresh session is created on the next connect().
        session?.finishTasksAndInvalidate()
        session = nil
    }

    func write(string: String, completion: (() -> Void)?) {
        task?.send(.string(string)) { _ in completion?() }
    }

    /// URLSession delivers one message per call, so each one re-arms the read.
    private func receiveNext() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let text)):
                onText?(text)
                receiveNext()
            case .success:
                receiveNext()
            case .failure(let error):
                isConnected = false
                onDisconnect?(error)
            }
        }
    }

    func urlSession(_: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        isConnected = true
        onConnect?()
    }

    func urlSession(_: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        onDisconnect?(nil)
    }
}

/// The SDK needs keccak and public-key recovery; both already ship with
/// web3swift's dependencies, so nothing new is pulled in for them.
private struct WalletCrypto: CryptoProvider {
    func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data {
        // web3swift wants the 65-byte r‖s‖v form with a recovery id of 0/1,
        // while Ethereum signatures are usually quoted with v as 27/28.
        var serialized = Data(signature.r) + Data(signature.s)
        serialized.append(signature.v >= 27 ? signature.v - 27 : signature.v)
        guard let key = SECP256K1.recoverPublicKey(hash: keccak256(message), signature: serialized) else {
            throw WalletConnectCryptoError.recoveryFailed
        }
        return key
    }

    func keccak256(_ data: Data) -> Data {
        Data(SHA3(variant: .keccak256).calculate(for: [UInt8](data)))
    }
}

enum WalletConnectCryptoError: Error { case recoveryFailed }

enum WalletConnectError: LocalizedError {
    case malformedRequest
    case signingFailed
    case unsupportedMethod(String)
    case wrongAccount

    var errorDescription: String? {
        switch self {
        case .malformedRequest: String.loc("The app sent a request this wallet could not read.")
        case .signingFailed: String.loc("Signing failed.")
        case .unsupportedMethod(let method): String.loc("This wallet does not support \(method).")
        case .wrongAccount: String.loc("This request is for a different wallet than the one you have open.")
        }
    }
}
