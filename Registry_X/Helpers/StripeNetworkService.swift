import Foundation

// MARK: - Response Models

struct PaymentIntentResponse: Codable {
    let clientSecret: String
    let intentId: String
    let amount: Int
    let currency: String
}

struct CheckoutSessionResponse: Codable {
    let sessionId: String
    let url: String
}

struct PaymentStatusResponse: Codable {
    let status: String
    let amount: Int
    let currency: String
}

// MARK: - Network Service

enum StripeNetworkError: Error {
    case invalidURL
    case noBackendConfigured
    case networkError(Error)
    case invalidResponse
    case serverError(String)
    
    var userMessage: String {
        switch self {
        case .invalidURL:
            return "Invalid backend URL configuration"
        case .noBackendConfigured:
            return "Stripe backend not configured. Please check Setup > Payments > Providers."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from payment server"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

class StripeNetworkService {
    private let backendURL: String
    
    init(backendURL: String) {
        self.backendURL = backendURL
    }
    
    // MARK: - Create Payment Intent (for Card payments)
    
    func createPaymentIntent(
        amount: Decimal,
        currency: String,
        description: String,
        lineItems: [[String: Any]]? = nil,
        metadata: [String: String] = [:]
    ) async throws -> PaymentIntentResponse {
        guard let url = URL(string: "\(backendURL)/create-payment-intent") else {
            throw StripeNetworkError.invalidURL
        }
        
        // Backend expects amount in base currency (e.g., 10.00 for $10)
        // Backend will convert to cents internally
        var requestBody: [String: Any] = [
            "amount": NSDecimalNumber(decimal: amount).doubleValue,
            "currency": currency.lowercased(),
            "description": description,
            "metadata": metadata
        ]
        
        // Add line items if provided
        if let lineItems = lineItems {
            requestBody["lineItems"] = lineItems
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StripeNetworkError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorDict["error"] as? String {
                throw StripeNetworkError.serverError(error)
            }
            throw StripeNetworkError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(PaymentIntentResponse.self, from: data)
    }
    
    // MARK: - Create Terminal Payment Intent (for Tap to Pay)
    
    func createTerminalPaymentIntent(
        amount: Decimal,
        currency: String,
        description: String,
        metadata: [String: String] = [:]
    ) async throws -> PaymentIntentResponse {
        guard let url = URL(string: "\(backendURL)/create-terminal-payment-intent") else {
            throw StripeNetworkError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "amount": NSDecimalNumber(decimal: amount).doubleValue,
            "currency": currency.lowercased(),
            "description": description,
            "metadata": metadata
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StripeNetworkError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorDict["error"] as? String {
                throw StripeNetworkError.serverError(error)
            }
            throw StripeNetworkError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(PaymentIntentResponse.self, from: data)
    }
    
    // MARK: - Create Checkout Session (for QR Code payments)
    
    func createCheckoutSession(
        amount: Decimal,
        currency: String,
        description: String,
        companyName: String? = nil,
        lineItems: [[String: Any]]? = nil,
        metadata: [String: String] = [:]
    ) async throws -> CheckoutSessionResponse {
        guard let url = URL(string: "\(backendURL)/create-checkout-session") else {
            throw StripeNetworkError.invalidURL
        }
        
        // Backend expects amount in base currency (e.g., 10.00 for $10)
        // Backend will convert to cents internally
        var requestBody: [String: Any] = [
            "amount": NSDecimalNumber(decimal: amount).doubleValue,
            "currency": currency.lowercased(),
            "description": description,
            "metadata": metadata,
            "successUrl": "\(backendURL)/success",
            "cancelUrl": "\(backendURL)/cancel"
        ]
        
        if let companyName = companyName {
            requestBody["companyName"] = companyName
        }
        
        if let lineItems = lineItems {
            requestBody["lineItems"] = lineItems
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StripeNetworkError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorDict["error"] as? String {
                throw StripeNetworkError.serverError(error)
            }
            throw StripeNetworkError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(CheckoutSessionResponse.self, from: data)
    }
    
    // MARK: - Check Payment Status
    
    func checkPaymentStatus(intentId: String) async throws -> PaymentStatusResponse {
        guard let url = URL(string: "\(backendURL)/payment-intent/\(intentId)") else {
            throw StripeNetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StripeNetworkError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw StripeNetworkError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(PaymentStatusResponse.self, from: data)
    }
    
    // MARK: - Check Session Status
    
    func checkSessionStatus(sessionId: String) async throws -> [String: Any] {
        guard let url = URL(string: "\(backendURL)/checkout-session/\(sessionId)") else {
            throw StripeNetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StripeNetworkError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw StripeNetworkError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        // Return raw dictionary to handle any status field format
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StripeNetworkError.invalidResponse
        }
        
        return json
    }
    
    // MARK: - Send Receipt Email
    
    func sendReceiptEmail(paymentIntentId: String, email: String) async throws -> Bool {
        guard let url = URL(string: "\(backendURL)/send-receipt-email") else {
            throw StripeNetworkError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "paymentIntentId": paymentIntentId,
            "email": email
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StripeNetworkError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorDict["error"] as? String {
                throw StripeNetworkError.serverError(error)
            }
            throw StripeNetworkError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        return true
    }
}
