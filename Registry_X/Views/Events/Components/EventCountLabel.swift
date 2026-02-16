import SwiftUI
import SwiftData

struct EventCountLabel: View {
    @Query private var events: [Event]
    
    init(userId: UUID?) {
        if let userId = userId {
            _events = Query(filter: #Predicate<Event> { $0.creatorId == userId })
        } else {
            // Match nothing safely
            let randomId = UUID()
            _events = Query(filter: #Predicate<Event> { $0.creatorId == randomId })
        }
    }
    
    var body: some View {
        Text("(\(events.count) total)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}
