import LocalAuthentication

enum Biometrics {
    /// The device's biometric name for UI labels: "Face ID", "Touch ID", "Optic ID",
    /// or a passcode fallback. Reflects the actual hardware.
    static var label: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String.loc("Passcode")
        }
    }
}
