import SwiftUI

enum Route: Hashable { case send, addWallet }

struct HomeView: View {
    @Environment(WalletStore.self) private var wallet
    @State private var path: [Route] = []
    @State private var showReceive = false
    @State private var showSwap = false
    @State private var showSettings = false
    @State private var selectedGroup: TokenGroup?
    @State private var showManage = false
    @State private var balances: [String: Decimal] = [:]
    @State private var prices: [String: Double] = [:]
    @State private var activity: [Activity] = []
    @State private var activityLimit = 5
    @State private var selectedActivity: Activity?
    @State private var refreshTrigger = 0
    @AppStorage("hiddenActivity") private var hiddenData = Data()
    @AppStorage("hideBalances") private var hideBalances = false

    private var totalUSD: Double {
        Token.all.reduce(0) { sum, token in
            guard let price = prices[token.priceKey],
                  let balance = balances[token.id] else { return sum }
            return sum + (balance as NSDecimalNumber).doubleValue * price
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        titleBar
                        header
                        actionButtons
                        tokenList
                        activitySection
                    }
                    .padding(20)
                }
                .refreshable { refreshTrigger += 1 }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                settingsButton
                walletMenu
            }
            .task(id: "\(refreshTrigger)-\(wallet.activeAddress ?? "")") { await refresh() }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .send: SendView { refreshTrigger += 1 }
                case .addWallet: OnboardingView()
                }
            }
            .sheet(isPresented: $showReceive) { ReceiveView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $selectedGroup) { CoinDetailView(group: $0, balances: balances) }
            .sheet(item: $selectedActivity) { ActivityDetailView(item: $0) }
            .sheet(isPresented: $showManage) { WalletManageView() }
            .sheet(isPresented: $showSwap) { SwapView { refreshTrigger += 1 } }
        }
    }

    /// Mirrors the wallet menu across the navigation bar, same glyph weight.
    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Haptic.tap()
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
    }

    private var walletMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach(wallet.wallets) { info in
                    Button {
                        Haptic.tap()
                        balances = [:]
                        wallet.select(info)
                    } label: {
                        if info.address == wallet.activeAddress {
                            Label(info.name, systemImage: "checkmark")
                        } else {
                            Text(info.name)
                        }
                    }
                }
                Divider()
                Button {
                    Haptic.tap()
                    path.append(.addWallet)
                } label: {
                    Label("Add Wallet", systemImage: "plus")
                }
                Button {
                    Haptic.tap()
                    showManage = true
                } label: {
                    Label("Manage Wallets", systemImage: "slider.horizontal.3")
                }
            } label: {
                Image(systemName: "wallet.bifold")
            }
        }
    }

    /// Read-only here — the name is edited in Manage Wallets, next to the wallet
    /// it belongs to.
    private var titleBar: some View {
        HStack(spacing: 8) {
            Text(wallet.activeWallet?.name ?? "AEIOT Wallet")
                .font(.largeTitle.bold())
                .oneLine()
            Spacer()
        }
        .padding(.top, 8)
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("Total Balance")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    Haptic.tap()
                    hideBalances.toggle()
                } label: {
                    Image(systemName: hideBalances ? "eye.slash" : "eye")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Text(hideBalances ? "••••" : totalUSD.formatted(.currency(code: "USD")))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                // A balance must never wrap or be cut off, so it shrinks far
                // enough to keep even a long figure on one line.
                .oneLine(0.4)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                Haptic.tap()
                path.append(.send)
            } label: {
                Label("Send", systemImage: "arrow.up")
                    .font(.subheadline).oneLine().frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)

            Button {
                Haptic.tap()
                showReceive = true
            } label: {
                Label("Receive", systemImage: "arrow.down")
                    .font(.subheadline).oneLine().frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.glass)

            Button {
                Haptic.tap()
                showSwap = true
            } label: {
                Label("Swap", systemImage: "arrow.left.arrow.right")
                    .font(.subheadline).oneLine().frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.glass)
        }
    }

    private var tokenList: some View {
        VStack(spacing: 12) {
            ForEach(Token.grouped) { group in
                groupRow(group)
            }
        }
    }

    /// Holdings of one coin summed across every network it lives on.
    private func total(of group: TokenGroup) -> Decimal {
        group.tokens.reduce(0) { $0 + (balances[$1.id] ?? 0) }
    }

    private func groupRow(_ group: TokenGroup) -> some View {
        let loaded = group.tokens.contains { balances[$0.id] != nil }
        let amount = total(of: group)
        return HStack(spacing: 12) {
            TokenLogo(token: group.primary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(group.symbol).font(.headline)
                    networkBadge(group)
                }
                Text(group.name).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if hideBalances {
                    Text("••••").font(.headline).foregroundStyle(.tertiary)
                } else if loaded {
                    Text(amount, format: .number.precision(.fractionLength(0...6)))
                        .font(.headline.monospacedDigit())
                        .oneLine(0.5)
                } else {
                    Text("···").foregroundStyle(.tertiary)
                }
                if hideBalances {
                    EmptyView()
                } else if let price = prices[group.primary.priceKey], loaded {
                    Text((amount as NSDecimalNumber).doubleValue * price,
                         format: .currency(code: "USD"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .oneLine(0.6)
                } else if group.primary.coingeckoID == nil {
                    Text("No market yet").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .contentShape(.rect)
        .onTapGesture {
            Haptic.tap()
            selectedGroup = group
        }
    }

    /// One network shows its name; several show how many there are.
    @ViewBuilder
    private func networkBadge(_ group: TokenGroup) -> some View {
        Group {
            if group.tokens.count == 1 {
                Text(group.primary.chain.name)
            } else {
                Text("\(group.tokens.count) networks")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .oneLine()
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary, in: .capsule)
    }

    private var hiddenIDs: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: hiddenData)) ?? []
    }

    private var visibleActivity: [Activity] {
        activity.filter { !hiddenIDs.contains($0.id) }
    }

    private func hideActivity(_ id: String) {
        var s = hiddenIDs
        s.insert(id)
        hiddenData = (try? JSONEncoder().encode(s)) ?? hiddenData
    }

    @ViewBuilder
    private var activitySection: some View {
        if !visibleActivity.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Activity")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(visibleActivity.prefix(activityLimit)) { item in
                    ActivityRow(item: item,
                                onTap: { selectedActivity = item },
                                onDelete: { hideActivity(item.id) })
                }
                if visibleActivity.count > activityLimit {
                    Button {
                        Haptic.tap()
                        activityLimit += 5
                    } label: {
                        Text("Show More")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    private func refresh() async {
        guard let address = wallet.address else { return }
        async let fetchedPrices = PriceService.usdPrices(for: Token.all)
        async let fetchedActivity = HistoryService.recentTransfers(
            evm: address,
            bitcoin: wallet.addresses(for: .bitcoin),
            solana: wallet.address(for: .solana),
            xrp: wallet.address(for: .xrp))
        // One request per coin across six networks — serial would take seconds.
        balances = await withTaskGroup(of: (String, Decimal)?.self) { group in
            for token in Token.all {
                // Each network has its own address; Bitcoin has a whole set of them.
                let owners = wallet.addresses(for: token.chain)
                guard !owners.isEmpty else { continue }
                group.addTask {
                    guard let balance = try? await ChainService.shared.balance(of: token, owners: owners)
                    else { return nil }
                    return (token.id, balance)
                }
            }
            var result: [String: Decimal] = [:]
            for await pair in group {
                if let pair { result[pair.0] = pair.1 }
            }
            return result
        }
        var newPrices = await fetchedPrices
        if let ethUSD = newPrices["ethereum"],
           let aeiotUSD = await PriceService.aeiotUSDPrice(ethUSD: ethUSD) {
            newPrices["aeiot"] = aeiotUSD
        }
        prices = newPrices
        activity = await fetchedActivity
    }
}
