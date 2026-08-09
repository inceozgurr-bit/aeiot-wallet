import SwiftUI

struct LockView: View {
    @Environment(WalletStore.self) private var wallet

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("AEIOT Wallet Locked")
                    .font(.title2.bold())
                Spacer()
                Button {
                    Haptic.tap()
                    Task { await wallet.unlock() }
                } label: {
                    Label(String.loc("Unlock with \(Biometrics.label)"), systemImage: "lock.open")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
            }
            .padding(24)
        }
        .task { await wallet.unlock() }
    }
}
