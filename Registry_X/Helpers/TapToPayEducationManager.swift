import SwiftUI
import Combine

/// Helper class to manage Tap to Pay on iPhone merchant education
/// Uses per-user tracking to ensure each user sees splash/education on their first login
@MainActor
class TapToPayEducationManager: ObservableObject {
    static let shared = TapToPayEducationManager()
    
    private let defaults = UserDefaults.standard
    private let splashPrefix = "tapToPaySplash_"
    private let termsPrefix = "tapToPayTerms_"
    private let educationPrefix = "tapToPayEducation_"
    
    private init() {}
    
    // MARK: - Per-User Tracking
    
    /// Check if splash should be shown for this user
    func shouldShowSplash(for userId: String) -> Bool {
        let key = splashPrefix + userId
        return !defaults.bool(forKey: key)
    }
    
    /// Mark splash as shown for this user
    func markSplashShown(for userId: String) {
        let key = splashPrefix + userId
        defaults.set(true, forKey: key)
    }
    
    /// Check if T&C has been accepted by this user
    func hasAcceptedTerms(for userId: String) -> Bool {
        let key = termsPrefix + userId
        return defaults.bool(forKey: key)
    }
    
    /// Mark T&C as accepted for this user
    func markTermsAccepted(for userId: String) {
        let key = termsPrefix + userId
        defaults.set(true, forKey: key)
    }
    
    /// Check if education has been completed by this user
    func hasCompletedEducation(for userId: String) -> Bool {
        let key = educationPrefix + userId
        return defaults.bool(forKey: key)
    }
    
    /// Mark education as completed for this user
    func markEducationComplete(for userId: String) {
        let key = educationPrefix + userId
        defaults.set(true, forKey: key)
    }
    
    // MARK: - Legacy Support (for backward compatibility)
    
    /// Legacy method - now requires userId
    @available(*, deprecated, message: "Use markEducationComplete(for:) instead")
    func markEducationComplete() {
        // This is called from education view without userId context
        // We'll need to get current user from AuthService
        // For now, this is a no-op - will be handled per-user
    }
    
    // MARK: - Testing/Debug
    
    /// Reset all flags for a specific user (for testing)
    func resetUser(_ userId: String) {
        defaults.removeObject(forKey: splashPrefix + userId)
        defaults.removeObject(forKey: termsPrefix + userId)
        defaults.removeObject(forKey: educationPrefix + userId)
    }
    
    /// Reset all users (for testing)
    func resetAll() {
        // Get all keys and remove Tap to Pay related ones
        let keys = defaults.dictionaryRepresentation().keys
        for key in keys {
            if key.hasPrefix(splashPrefix) || 
               key.hasPrefix(termsPrefix) || 
               key.hasPrefix(educationPrefix) {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
