import Foundation

/// Service for sending event-related email notifications
@MainActor
class EventNotificationService {
    
    private static let mailerBackendURL = "https://registry-x-mailer-364250874736.europe-west1.run.app"
    
    /// Send an email notification when an event is finalised
    /// - Parameters:
    ///   - eventName: Name of the finalised event
    ///   - username: Full name of the user who finalised the event
    ///   - totalAmount: Total gross sales formatted with currency symbol
    ///   - recipientEmails: Array of email addresses to send to
    ///   - xlsData: Optional XLS file data to attach
    ///   - xlsFilename: Filename for the XLS attachment
    static func sendFinalisationEmail(
        eventName: String,
        username: String,
        totalAmount: String,
        recipientEmails: [String],
        xlsData: Data? = nil,
        xlsFilename: String = "event_export.xlsx"
    ) {
        guard let url = URL(string: "\(mailerBackendURL)/event-finalised") else {
            print("Invalid mailer backend URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var payload: [String: Any] = [
            "eventName": eventName,
            "username": username,
            "totalAmount": totalAmount,
            "recipients": recipientEmails,
            "fromName": "Registry X - Event finalised",
            "fromEmail": "registry-x@newmagicstuff.com"
        ]
        
        // Add XLS attachment if provided
        if let xlsData = xlsData {
            let base64XLS = xlsData.base64EncodedString()
            payload["xlsBase64"] = base64XLS
            payload["xlsFilename"] = xlsFilename
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            // Fire and forget - don't block finalisation if email fails
            Task {
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        if httpResponse.statusCode != 200 {
                            let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                            print("Failed to send finalisation email: \(errorString)")
                        }
                    }
                } catch {
                    print("Network error sending finalisation email: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Encoding error for finalisation email: \(error.localizedDescription)")
        }
    }
}
