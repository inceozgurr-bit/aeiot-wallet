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
    var proposal: Session.Proposal?
    /// A dapp asking for a signature.
    var request: Request?
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

        WalletKit.instance.sessionProposalPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] proposal, _ in self?.proposal = proposal }
            .store(in: &cancellables)

        WalletKit.instance.sessionRequestPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request, _ in self?.request = request }
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
        guard let uri = WalletConnectURI(string: scanned) else { return }
        do {
            try await WalletKit.instance.pair(uri: uri)
        } catch {
            failure = error.localizedDescription
        }
    }

    func approve(_ proposal: Session.Proposal, address: String) async {
        do {
            let namespaces = try AutoNamespaces.build(
                sessionProposal: proposal,
                chains: Self.requestedChains(in: proposal),
                methods: Array(proposal.requiredNamespaces.values.flatMap(\.methods)),
                events: Array(proposal.requiredNamespaces.values.flatMap(\.events)),
                accounts: Self.requestedChains(in: proposal).compactMap {
                    Account(blockchain: $0, address: address)
                }
            )
            _ = try await WalletKit.instance.approve(proposalId: proposal.id, namespaces: namespaces)
        } catch {
            failure = error.localizedDescription
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

    /// Answers a signing request with a result the dapp can use.
    func respond(_ request: Request, result: String) async {
        do {
            try await WalletKit.instance.respond(topic: request.topic,
                                                 requestId: request.id,
                                                 response: .response(AnyCodable(result)))
        } catch {
            failure = error.localizedDescription
        }
        self.request = nil
    }

    /// Turns the dapp down. Also used for the methods we deliberately refuse.
    func decline(_ request: Request, reason: String = "User rejected") async {
        try? await WalletKit.instance.respond(
            topic: request.topic,
            requestId: request.id,
            response: .error(JSONRPCError(code: 4001, message: reason)))
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
        let keystore = try await wallet.loadKeystore()
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

    /// Both CryptoSwift and web3swift define `toHexString()`, so spelling it out
    /// avoids an ambiguous call.
    private static func hex(_ data: Data) -> String {
        "0x" + data.map { String(format: "%02x", $0) }.joined()
    }

    /// What the confirmation sheet shows the user before they approve. Nothing
    /// here is trusted — it is the dapp's own text, rendered as text.
    static func readableMessage(for request: Request) -> String {
        switch request.method {
        case "personal_sign":
            guard let params = try? request.params.get([String].self), let raw = params.first
            else { return request.method }
            if let data = Data.fromHex(raw), let text = String(data: data, encoding: .utf8) {
                return text
            }
            return raw
        case "eth_signTypedData", "eth_signTypedData_v4":
            return (try? request.params.get([String].self))?.last ?? request.method
        default:
            return request.method
        }
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
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    init(url: URL) {
        request = URLRequest(url: url)
        super.init()
    }

    func connect() {
        task = session.webSocketTask(with: request)
        task?.resume()
        receiveNext()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
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

    var errorDescription: String? {
        switch self {
        case .malformedRequest: String.loc("The app sent a request this wallet could not read.")
        case .signingFailed: String.loc("Signing failed.")
        case .unsupportedMethod(let method): String.loc("This wallet does not support \(method).")
        }
    }
}
