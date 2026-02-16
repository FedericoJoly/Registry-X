import Foundation

/// Configuration for Stripe payment integration per event
struct StripeConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var publishableKey: String
    var backendURL: String
    var companyName: String
    var locationId: String // Terminal Location ID for Tap to Pay
    
    /// Validates the configuration if integration is enabled
    var isValid: Bool {
        guard isEnabled else { return true } // Valid if disabled
        return !publishableKey.isEmpty &&
               !backendURL.isEmpty &&
               publishableKey.hasPrefix("pk_") &&
               (backendURL.hasPrefix("http://") || backendURL.hasPrefix("https://"))
    }
    
    init(
        isEnabled: Bool = false,
        publishableKey: String = "",
        backendURL: String = "",
        companyName: String = "",
        locationId: String = ""
    ) {
        self.isEnabled = isEnabled
        self.publishableKey = publishableKey
        self.backendURL = backendURL
        self.companyName = companyName
        self.locationId = locationId
    }
}
