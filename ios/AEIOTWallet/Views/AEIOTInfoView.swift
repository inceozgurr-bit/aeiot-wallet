import SwiftUI

struct AEIOTInfoView: View {
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image("AEIOTLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .scaleEffect(appeared ? 1 : 0.7)
                    .animation(.bouncy, value: appeared)
                    .onAppear { appeared = true }

                Text("A fixed-supply coin on the Base network. Only 1,150,115 AEIOT exist and no more can ever be created.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    infoRow("Total Supply", "\(1_150_115.formatted()) AEIOT")
                    infoRow("Network", "Base")
                    infoRow("Standard", "ERC-20")
                }
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 18))

                Link(destination: Token.aeiot.chain.tokenURL(Token.aeiot.contract ?? "")!) {
                    Label("View on Basescan", systemImage: "safari")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
            }
            .padding(24)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("About AEIOT")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }
}
