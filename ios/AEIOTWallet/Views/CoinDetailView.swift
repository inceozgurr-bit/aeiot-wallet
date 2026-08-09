import SwiftUI
import Charts

struct CoinDetailView: View {
    let group: TokenGroup
    let balances: [String: Decimal]

    @State private var days = 7
    @State private var prices: [Double] = []
    @State private var isLoading = true

    private let ranges: [(label: LocalizedStringKey, days: Int)] = [
        ("24H", 1), ("7D", 7), ("30D", 30), ("1Y", 365),
    ]

    /// Price and artwork are the same on every network, so the first one stands in.
    private var token: Token { group.primary }

    private var current: Double? { prices.last }
    private var changePercent: Double? {
        guard let first = prices.first, first > 0, let last = prices.last else { return nil }
        return (last - first) / first * 100
    }
    private var isUp: Bool { (changePercent ?? 0) >= 0 }
    /// One accent only — direction is carried by the arrow glyph and the sign.
    private var trendColor: Color { isUp ? .appAccent : .secondary }

    private var isAEIOT: Bool { group.symbol == "AEIOT" }
    private var hasMarket: Bool { token.coingeckoID != nil || isAEIOT }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if group.tokens.count > 1 {
                    networkBreakdown
                }
                if hasMarket {
                    rangePicker
                    chart
                } else {
                    notListed
                }
            }
            .padding(24)
            .padding(.top, 40)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
        .task(id: days) { await load() }
    }

    private var notListed: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Not on the market yet")
                .font(.headline)
            Text("Once a liquidity pool opens for AEIOT, its live price and chart will appear here automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 30)
    }

    private var header: some View {
        VStack(spacing: 10) {
            TokenLogo(token: token, size: 52)
            Text(group.name).font(.headline)
            if group.tokens.count == 1 {
                Text(token.chain.name).font(.caption).foregroundStyle(.secondary)
            }
            if !hasMarket {
                EmptyView()
            } else if let current {
                Text(current, format: .currency(code: "USD").precision(.fractionLength(current < 1 ? 4 : 2)))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                if let changePercent {
                    Label(changePercent.formatted(.number.precision(.fractionLength(2))) + "%",
                          systemImage: isUp ? "arrow.up.right" : "arrow.down.right")
                        .font(.subheadline.bold())
                        .foregroundStyle(trendColor)
                }
            } else if isLoading {
                ProgressView().padding(.top, 8)
            } else {
                Text("Price unavailable").foregroundStyle(.secondary)
            }
        }
    }

    /// Where the coin actually sits, network by network.
    private var networkBreakdown: some View {
        VStack(spacing: 12) {
            Text("Balance by network")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(group.tokens) { item in
                HStack {
                    Text(item.chain.name)
                    Spacer()
                    if let balance = balances[item.id] {
                        Text(balance, format: .number.precision(.fractionLength(0...6)))
                            .monospacedDigit()
                    } else {
                        Text("···").foregroundStyle(.tertiary)
                    }
                }
                .font(.subheadline)
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var rangePicker: some View {
        Picker("Range", selection: $days) {
            ForEach(ranges, id: \.days) { Text($0.label).tag($0.days) }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var chart: some View {
        if prices.count > 1 {
            Chart(Array(prices.enumerated()), id: \.offset) { index, price in
                LineMark(x: .value("t", index), y: .value("price", price))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(trendColor)
                AreaMark(x: .value("t", index), y: .value("price", price))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        .linearGradient(colors: [trendColor.opacity(0.25), .clear],
                                        startPoint: .top, endPoint: .bottom))
            }
            .chartXAxis(.hidden)
            .chartYScale(domain: (prices.min() ?? 0)...(prices.max() ?? 1))
            .frame(height: 200)
        } else if isLoading {
            ProgressView().frame(height: 200)
        } else {
            Text("No chart data").foregroundStyle(.secondary).frame(height: 200)
        }
    }

    private func load() async {
        isLoading = true
        if isAEIOT {
            prices = await PriceService.aeiotChart(days: days)
        } else if let id = token.coingeckoID {
            prices = await PriceService.chart(for: id, days: days)
        }
        isLoading = false
    }
}
