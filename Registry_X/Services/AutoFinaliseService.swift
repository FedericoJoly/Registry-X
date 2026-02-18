import Foundation
import UserNotifications
import SwiftData

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
    
    /// Cancel the scheduled notification for an event (e.g. manually finalised or closed date cleared).
    func cancelNotification(for event: Event) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationId(for: event)])
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
            
            // Finalise
            event.isFinalised = true
            event.isLocked = true
            event.closingDate = nil
            cancelNotification(for: event)
        }
        
        try? modelContext.save()
    }
    
    // MARK: - Helpers
    
    private func notificationId(for event: Event) -> String {
        "autofinalise-\(event.id.uuidString)"
    }
}
