import LocalAuthentication

enum Biometrics {
    /// The device's biometric name for UI labels: "Face ID", "Touch ID", "Optic ID",
    /// or a passcode fallback. Reflects the actual hardware.
    /// Resolved once: every read allocates an LAContext and makes a synchronous
    /// call to the biometry daemon, and this string is read from view bodies
    /// that redraw constantly. The hardware does not change while running.
    static let label: String = {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String.loc("Passcode")
        }
    }()
}
