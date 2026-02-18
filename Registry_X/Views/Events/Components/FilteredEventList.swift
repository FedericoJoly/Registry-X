import SwiftUI
import SwiftData

struct FilteredEventList: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var events: [Event]
    
    // Callbacks passed from Parent
    let onDuplicate: (Event) -> Void
    let onLockStateChange: (Event) -> Void
    let onDelete: (Event) -> Void
    
    // Incremented when auto-finalise fires to force a re-render
    @State private var refreshID = UUID()
    
    init(userId: UUID?, onDuplicate: @escaping (Event) -> Void, onLockStateChange: @escaping (Event) -> Void, onDelete: @escaping (Event) -> Void) {
        self.onDuplicate = onDuplicate
        self.onLockStateChange = onLockStateChange
        self.onDelete = onDelete
        
        let sortDescriptors = [SortDescriptor(\Event.lastModified, order: .reverse)]
        
        if let userId = userId {
            _events = Query(filter: #Predicate<Event> { event in
                event.creatorId == userId
            }, sort: sortDescriptors)
        } else {
            // Fallback for when no user is logged in (shouldn't happen in this view) or admin?
            // User said "Events should only be visible by the user who created them"
            // So default to empty or maybe all? Let's show empty for safety.
            // Actually, predicates with optional UUIDs are tricky.
            // Let's try to match a non-existent ID or just show nothing.
            // Since we can't easily make a "False" predicate that compiles cleanly sometimes,
            // we will query all but filter in body? No, that defeats the purpose.
            // We'll trust userId is present. If nil, we show none.
            // Safest bet for "Nothing": ID == UUID() (random)
            let randomId = UUID()
            _events = Query(filter: #Predicate<Event> { event in
                event.creatorId == randomId
            }, sort: sortDescriptors)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                if events.isEmpty {
                    ContentUnavailableView("No Events", systemImage: "calendar.badge.plus", description: Text("Create your first event to get started."))
                        .padding(.top, 40)
                } else {
                    ForEach(events) { event in
                        EventCard(
                            event: event,
                            onDuplicate: { onDuplicate(event) },
                            onLockStateChange: { onLockStateChange(event) },
                            onDelete: { onDelete(event) }
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .padding(.bottom, 80)
        }
        .id(refreshID) // Force re-render when auto-finalise fires
        .onReceive(NotificationCenter.default.publisher(for: .eventDidAutoFinalise)) { _ in
            refreshID = UUID()
        }
    }
}
