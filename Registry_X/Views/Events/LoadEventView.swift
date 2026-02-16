import SwiftUI
import SwiftData

struct LoadEventView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var events: [Event]
    
    @State private var searchText = ""
    var onSelect: (Event) -> Void
    
    init(userId: UUID?, onSelect: @escaping (Event) -> Void) {
        self.onSelect = onSelect
        let sortDescriptors = [SortDescriptor(\Event.lastModified, order: .reverse)]
        if let userId = userId {
            _events = Query(filter: #Predicate<Event> { $0.creatorId == userId }, sort: sortDescriptors)
        } else {
            let randomId = UUID()
            _events = Query(filter: #Predicate<Event> { $0.creatorId == randomId }, sort: sortDescriptors)
        }
    }
    
    var filteredEvents: [Event] {
        if searchText.isEmpty {
            return events
        } else {
            return events.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if filteredEvents.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(filteredEvents) { event in
                        Button(action: {
                            onSelect(event)
                            dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.name)
                                        .font(.headline)
                                    
                                    Text(event.date.formatted(date: .numeric, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.gray)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                            }
                            .padding(.vertical, 4)
                            .foregroundStyle(.primary) // Adaptive text color
                        }
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by name")
            .navigationTitle("Load Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    LoadEventView(userId: nil, onSelect: { _ in })
        .modelContainer(for: Event.self, inMemory: true)
}
