import Foundation

/// Service for sending custom email receipts for non-Stripe payment methods
@MainActor
class ReceiptService {
    
    /// Send a custom receipt email via the mailer backend
    /// - Parameters:
    ///   - transaction: The transaction to generate receipt for
    ///   - event: The event associated with the transaction
    ///   - email: Customer's email address
    ///   - mailerBackendURL: URL of the botonera-x-mailer service
    /// - Returns: Success status and optional error message
    static func sendCustomReceipt(
        transaction: Transaction,
        event: Event,
        email: String,
        mailerBackendURL: String = "https://registry-x-mailer-364250874736.europe-west1.run.app"
    ) async -> (success: Bool, error: String?) {
        // Validate email format
        guard isValidEmail(email) else {
            return (false, "Invalid email address")
        }
        
        // Generate HTML content
        let htmlContent = ReceiptTemplate.generateReceiptHTML(
            event: event,
            transaction: transaction,
            customerEmail: email
        )
        
        // Generate subject
        let subject = ReceiptTemplate.generateSubject(eventName: event.name)
        
        // Prepare request
        guard let url = URL(string: "\(mailerBackendURL)/send-receipt") else {
            return (false, "Invalid backend URL")
        }
        
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: String] = [
            "email": email,
            "subject": subject,
            "html": htmlContent,
            "fromName": event.fromName ?? "Sales Team",
            "fromEmail": event.fromEmail ?? "sales@example.com"
        ]
        
        do {
            request.httpBody = try JSONEncoder().encode(payload)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "Invalid response from server")
            }
            
            
            if httpResponse.statusCode == 200 {
                // Success
                return (true, nil)
            } else {
                // Server error
                if let errorMessage = try? JSONDecoder().decode([String: String].self, from: data),
                   let error = errorMessage["error"] {
                    return (false, "Server error: \(error)")
                }
                return (false, "Server returned error code \(httpResponse.statusCode)")
            }
        } catch {
            return (false, "Network error: \(error.localizedDescription)")
        }
    }
    
    /// Validates email address format
    private static func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    /// Checks if a payment method should use custom (non-Stripe) receipts
    static func usesCustomReceipt(paymentMethod: PaymentMethod) -> Bool {
        switch paymentMethod {
        case .cash, .transfer, .other:
            // Cash, Transfer, and Other (which includes Bizum) use custom receipts
            return true
        case .card:
            // Card payments use Stripe receipts
            return false
        }
    }
    
    /// Checks if receipt prompt should be shown based on event settings
    static func shouldShowReceiptPrompt(
        for paymentMethod: PaymentMethod,
        event: Event
    ) -> Bool {
        // Load receipt settings
        guard let data = event.receiptSettingsData,
              let settings = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            return false  // Default: disabled
        }
        
        // Map payment method to setting key
        let settingKey: String
        switch paymentMethod {
        case .cash:
            settingKey = "Cash"
        case .card:
            settingKey = "Card"
        case .transfer:
            settingKey = "Transfer"
        case .other:
            // Check all "other" payments by their method name
            return settings["Bizum"] == true || settings["Tap to Pay"] == true
        }
        
        return settings[settingKey] == true
    }
}
