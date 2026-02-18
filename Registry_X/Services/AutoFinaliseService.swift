import Foundation
import UserNotifications
import SwiftData

extension Notification.Name {
    static let eventDidAutoFinalise = Notification.Name("eventDidAutoFinalise")
}

/// Handles scheduling and checking auto-finalise for all events.
/// - Schedules a local notification at each event's closing date
/// - On app foreground, checks all events and finalises any that are overdue
@MainActor
class AutoFinaliseService {
    
    static let shared = AutoFinaliseService()
    private init() {}
    
    // MARK: - Notification Permission
    
    func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    // MARK: - Schedule Notification
    
    /// Schedule (or reschedule) a local notification for an event's closing date.
    /// Call this whenever closingDate is saved.
    func scheduleNotification(for event: Event) {
        guard let closingDate = event.closingDate, !event.isFinalised else {
            cancelNotification(for: event)
            return
        }
        
        let center = UNUserNotificationCenter.current()
        let identifier = notificationId(for: event)
        
        // Remove existing
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        
        // Don't schedule if date is in the past
        guard closingDate > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Event Auto-Finalised"
        content.body = "'\(event.name)' has been automatically finalised."
        content.sound = .default
        
        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: closingDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("AutoFinalise: failed to schedule notification: \(error)")
            }
        }
    }
    
    /// Cancel the scheduled notification for an event (e.g. manually finalised or closing date cleared).
    func cancelNotification(for event: Event) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationId(for: event)])
    }
    
    // MARK: - Core Finalise Logic
    
    /// Finalise a single event: generate PIN, lock, mark finalised, send email.
    /// This is the single source of truth for finalisation — called by both
    /// SetupView (manual/timer) and the foreground check (background auto-finalise).
    func finaliseEvent(_ event: Event, modelContext: ModelContext, username: String, creatorEmail: String?) {
        guard !event.isFinalised else { return }
        
        // Generate PIN from current date (YYMMDD format)
        let generatedPIN = event.generateDatePIN()
        
        event.pinCode = generatedPIN
        event.isLocked = true
        event.isFinalised = true
        event.closingDate = nil
        
        cancelNotification(for: event)
        try? modelContext.save()
        
        // Notify UI to refresh
        NotificationCenter.default.post(name: .eventDidAutoFinalise, object: nil)
        
        // Calculate total gross sales in main currency
        let mainCurrency = event.currencies.first(where: { $0.isMain })
        let currencySymbol = mainCurrency?.symbol ?? "$"
        let mainCode = mainCurrency?.code ?? event.currencyCode
        
        var total = Decimal(0)
        for transaction in event.transactions {
            let amount = transaction.totalAmount
            if transaction.currencyCode == mainCode {
                total += amount
            } else {
                let rate = event.currencies.first(where: { $0.code == transaction.currencyCode })?.rate ?? 1.0
                if rate > 0 { total += amount / rate }
            }
        }
        let formattedTotal = "\(currencySymbol)\(total.formatted(.number.precision(.fractionLength(2))))"
        
        // Build recipient list
        var recipients: [String] = ["federico.joly@gmail.com"]
        if let email = creatorEmail, !email.isEmpty {
            recipients.insert(email, at: 0)
        }
        
        // Generate XLS and send email
        let xlsData = ExcelExportService.generateExcelData(event: event, username: username)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let xlsFilename = "\(event.name)_\(timestamp).xlsx"
        
        EventNotificationService.sendFinalisationEmail(
            eventName: event.name,
            username: username,
            totalAmount: formattedTotal,
            recipientEmails: recipients,
            xlsData: xlsData,
            xlsFilename: xlsFilename
        )
    }
    
    // MARK: - Foreground Check
    
    /// Call this every time the app comes to foreground.
    /// Finalises any events whose closing date has passed.
    func checkAndFinaliseOverdueEvents(modelContext: ModelContext) {
        let now = Date()
        let descriptor = FetchDescriptor<Event>()
        guard let events = try? modelContext.fetch(descriptor) else { return }
        
        for event in events {
            guard let closingDate = event.closingDate,
                  !event.isFinalised,
                  now >= closingDate else { continue }
            
            // Look up creator email
            var creatorEmail: String? = nil
            if let creatorId = event.creatorId {
                let userDescriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == creatorId })
                creatorEmail = (try? modelContext.fetch(userDescriptor).first)?.email
            }
            
            finaliseEvent(
                event,
                modelContext: modelContext,
                username: event.creatorName,
                creatorEmail: creatorEmail
            )
        }
    }
    
    // MARK: - Helpers
    
    private func notificationId(for event: Event) -> String {
        "autofinalise-\(event.id.uuidString)"
    }
}
