import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("themeMode") private var themeMode = ThemeMode.light
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.deviceDefault
    @AppStorage("requireBiometricUnlock") private var requireBiometricUnlock = true
    @State private var showLanguagePicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        appearanceCard
                        securityCard
                        aboutCard
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Appearance

    private var appearanceCard: some View {
        VStack(spacing: 0) {
            themeRow
            Divider().padding(.leading, 52)
            languageRow
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var themeRow: some View {
        HStack(spacing: 12) {
            icon(themeMode.icon)
            Text(themeMode.label)
            Spacer()
            HStack(spacing: 4) {
                ForEach(ThemeMode.allCases) { mode in
                    themeSegment(mode)
                }
            }
            .padding(4)
            .background(.ultraThinMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.15)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func themeSegment(_ mode: ThemeMode) -> some View {
        let isActive = themeMode == mode
        return Button {
            Haptic.tap()
            themeMode = mode
        } label: {
            Image(systemName: mode.icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 28)
                .foregroundStyle(isActive ? Color.appAccent : .secondary)
                .background(Capsule().fill(isActive ? Color.appAccent.opacity(0.14) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.label)
    }

    /// Changed inside the app, not in iOS Settings. A popover anchored to the
    /// row rather than a full-width menu sheet.
    private var languageRow: some View {
        Button {
            Haptic.tap()
            showLanguagePicker = true
        } label: {
            HStack(spacing: 12) {
                icon("globe")
                Text("Language")
                Spacer()
                Text(appLanguage.label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                chevron
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showLanguagePicker,
                 attachmentAnchor: .point(.trailing),
                 arrowEdge: .trailing) {
            languagePicker
        }
    }

    private var languagePicker: some View {
        VStack(spacing: 0) {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    Haptic.tap()
                    showLanguagePicker = false
                    appLanguage = language
                    Localization.apply(language)
                } label: {
                    HStack(spacing: 10) {
                        Text(language.label)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.footnote.bold())
                            .foregroundStyle(Color.appAccent)
                            .opacity(language == appLanguage ? 1 : 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if language != AppLanguage.allCases.last {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .frame(width: 190)
        // Without this iOS turns the popover into a full-width sheet on iPhone.
        .presentationCompactAdaptation(.popover)
    }

    // MARK: Security

    private var securityCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $requireBiometricUnlock) {
                HStack(spacing: 12) {
                    icon("faceid")
                    Text("Unlock with \(Biometrics.label)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().padding(.leading, 52)

            Text("Sending coins and revealing your recovery phrase always ask for \(Biometrics.label), even when this is off.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    // MARK: About

    private var aboutCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                AEIOTInfoView()
            } label: {
                row("info.circle", "About AEIOT")
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 52)

            NavigationLink {
                LegalView(document: .terms)
            } label: {
                row("doc.text", "Terms of Use")
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 52)

            NavigationLink {
                LegalView(document: .privacy)
            } label: {
                row("hand.raised", "Privacy Policy")
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 52)

            HStack(spacing: 12) {
                icon("number")
                Text("Version")
                Spacer()
                Text(appVersion).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    // MARK: Shared row pieces

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.body)
            .foregroundStyle(Color.appAccent)
            .frame(width: 24)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    private func row(_ iconName: String, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            icon(iconName)
            Text(title)
            Spacer()
            chevron
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
}
