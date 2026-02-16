import LocalAuthentication
import Foundation

/// Manager for biometric authentication (Face ID / Touch ID)
class BiometricAuthManager {
    static let shared = BiometricAuthManager()
    
    enum BiometricType {
        case faceID
        case touchID
        case none
    }
    
    /// Check if biometric authentication is available on this device
    func isBiometricAvailable() -> Bool {
        let context = LAContext() // Create fresh context each time
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// Get the type of biometric authentication available
    func biometricType() -> BiometricType {
        guard isBiometricAvailable() else { return .none }
        
        let context = LAContext() // Create fresh context each time
        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            return .faceID // Treat OpticID similar to FaceID
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }
    
    /// Authenticate user with biometrics
    /// - Parameter reason: The reason shown to the user
    /// - Returns: True if authentication succeeded
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch {
            return false
        }
    }
    
    /// Get user-friendly name for biometric type
    func biometricName() -> String {
        switch biometricType() {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .none:
            return "Biometric"
        }
    }
}
