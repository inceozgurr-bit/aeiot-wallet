import SwiftUI

/// First-run onboarding at the root, and "Add Wallet" flow when presented as a sheet.
struct OnboardingView: View {
    @Environment(WalletStore.self) private var wallet
    @Environment(\.dismiss) private var dismiss
    @State private var mnemonic: String?
    @State private var importPhrase = ""
    @State private var showImport = false
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var screenGuard = ScreenGuard()
    /// Which words we ask back, and what the user answered.
    @State private var quizIndices: [Int] = []
    @State private var quizAnswers: [Int: String] = [:]
    @State private var quizFailed = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            if let mnemonic {
                backupView(mnemonic)
            } else {
                welcomeView
            }
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image("AEIOTLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
            Text("AEIOT Wallet")
                .font(.largeTitle.bold())
            Text("Your keys, your coins. Stored only on this device.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()

            Button {
                Haptic.tap()
                createWallet()
            } label: {
                Text(isWorking ? String.loc("Creating…") : String.loc("Create New Wallet"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .disabled(isWorking)

            Button {
                Haptic.tap()
                showImport = true
            } label: {
                Text("Import Existing Wallet")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glass)

            if let errorMessage {
                Text(errorMessage).foregroundStyle(Color.appAccent).font(.footnote)
            }
        }
        .padding(24)
        .sheet(isPresented: $showImport) { importSheet }
    }

    private func backupView(_ phrase: String) -> some View {
        let words = phrase.split(separator: " ").map(String.init)
        return VStack(spacing: 20) {
            Text("Your Recovery Phrase")
                .font(.title2.bold())
            Text("Write these 12 words on paper, in order. Anyone with these words controls your coins. If you lose them, nobody can recover your wallet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    HStack(spacing: 4) {
                        Text("\(index + 1).").foregroundStyle(.tertiary).font(.caption)
                        Text(word).font(.callout.monospaced())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .glassEffect(.regular, in: .rect(cornerRadius: 10))
                }
            }
            // A screen recording would capture the phrase silently.
            .hiddenWhileRecording(screenGuard)
            .onAppear { prepareQuiz(wordCount: words.count) }

            if screenGuard.screenshotTaken {
                Label("A screenshot was taken. Photos are not a safe place for these words — delete it.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.appAccent)
                    .multilineTextAlignment(.center)
            }

            // Asking a few words back is what makes people actually write them
            // down — losing the phrase is the most common way funds disappear.
            VStack(alignment: .leading, spacing: 10) {
                Text("Confirm you wrote them down")
                    .font(.subheadline.weight(.medium))
                ForEach(quizIndices, id: \.self) { index in
                    HStack(spacing: 10) {
                        Text("\(index + 1).")
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                        TextField("word", text: Binding(
                            get: { quizAnswers[index] ?? "" },
                            set: { quizAnswers[index] = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                        .padding(8)
                        .glassEffect(.regular, in: .rect(cornerRadius: 10))
                    }
                }
                if quizFailed {
                    Text("Those do not match. Check the words above.")
                        .font(.caption)
                        .foregroundStyle(Color.appAccent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
            Button {
                Haptic.tap()
                guard quizPasses(words) else {
                    quizFailed = true
                    return
                }
                confirmBackup(phrase)
            } label: {
                Text(isWorking ? String.loc("Setting Up…") : String.loc("I Wrote It Down — Continue"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .disabled(isWorking)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(Color.appAccent).font(.footnote)
            }
        }
        .padding(24)
    }

    private var importSheet: some View {
        VStack(spacing: 20) {
            Text("Import Wallet").font(.title2.bold())
            Text("Enter your 12-word recovery phrase, separated by spaces.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("word1 word2 word3 …", text: $importPhrase, axis: .vertical)
                .lineLimit(3...5)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
            Button {
                Haptic.tap()
                importWallet()
            } label: {
                Text(isWorking ? String.loc("Importing…") : String.loc("Import"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .disabled(isWorking || importPhrase.isEmpty)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(Color.appAccent).font(.footnote)
            }
            Spacer()
        }
        .padding(24)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
    }

    /// Three words, drawn once so they do not reshuffle while typing.
    private func prepareQuiz(wordCount: Int) {
        guard quizIndices.isEmpty, wordCount > 0 else { return }
        quizIndices = Array(0..<wordCount).shuffled().prefix(3).sorted()
    }

    private func quizPasses(_ words: [String]) -> Bool {
        quizIndices.allSatisfy { index in
            let typed = (quizAnswers[index] ?? "")
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            return typed == words[index].lowercased()
        }
    }

    private func createWallet() {
        isWorking = true
        errorMessage = nil
        do {
            mnemonic = try wallet.createWallet()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func confirmBackup(_ phrase: String) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await wallet.confirmBackup(mnemonic: phrase)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func importWallet() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await wallet.importWallet(mnemonic: importPhrase)
                showImport = false
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
