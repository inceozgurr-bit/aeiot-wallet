import SwiftUI

struct ActivityRow: View {
    let item: Activity
    var onTap: () -> Void
    var onDelete: () -> Void

    private let revealWidth: CGFloat = 76

    private var titleKey: LocalizedStringKey { item.isIncoming ? "Received" : "Sent" }

    // A nested horizontal scroll view, not a DragGesture: the system splits the
    // axes itself, so vertical scrolling still reaches the list underneath.
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    .containerRelativeFrame(.horizontal)
                    .contentShape(.rect)
                    .onTapGesture {
                        Haptic.tap()
                        onTap()
                    }
                deleteButton
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }

    private var deleteButton: some View {
        Button(role: .destructive, action: onDelete) {
            Image(systemName: "trash")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: revealWidth)
                .frame(maxHeight: .infinity)
                .background(Color.appAccent, in: .rect(cornerRadius: 16))
        }
        .accessibilityLabel("Delete")
    }

    private var content: some View {
        HStack {
            Image(systemName: item.isIncoming ? "arrow.down.left" : "arrow.up.right")
                .foregroundStyle(item.isIncoming ? Color.appAccent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey).font(.subheadline)
                Text(item.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(item.isIncoming ? "+" : "-")\(item.amount.formatted(.number.precision(.fractionLength(0...4)))) \(item.symbol)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(item.isIncoming ? Color.appAccent : .primary)
        }
        .padding(14)
    }
}

struct ActivityDetailView: View {
    let item: Activity

    private var titleKey: LocalizedStringKey { item.isIncoming ? "Received" : "Sent" }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: item.isIncoming ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(item.isIncoming ? Color.appAccent : .secondary)
            Text(titleKey).font(.title3.bold())
            Text("\(item.isIncoming ? "+" : "-")\(item.amount.formatted(.number.precision(.fractionLength(0...6)))) \(item.symbol)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(item.isIncoming ? Color.appAccent : .primary)

            VStack(spacing: 12) {
                detailRow("Network", item.chain.name)
                Divider()
                detailRow("Date", item.date.formatted(date: .abbreviated, time: .shortened))
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transaction").font(.subheadline).foregroundStyle(.secondary)
                    Text(item.hash).font(.caption.monospaced()).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 16))

            if let url = item.chain.transactionURL(item.hash) {
                Link(destination: url) {
                    Label("View in Explorer", systemImage: "safari")
                        .font(.subheadline)
                }
            }
            Spacer()
        }
        .padding(24)
        .padding(.top, 20)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    private func detailRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }
}
