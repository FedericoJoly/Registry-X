import SwiftUI
import SwiftData

struct CreateEventView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var authService // Access current user
    @Query private var allEvents: [Event] // To check duplicates
    
    @State private var name: String = ""
    @State private var date: Date = Date()
    @State private var currencyCode: String = "USD"
    @State private var duplicateError = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Event Name", text: $name)
                        .font(.title3)
                } header: {
                    Text("Name")
                }
            }
            .navigationTitle("New Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createEvent()
                    }
                    .bold()
                    .tint(.blue)
                    .disabled(name.isEmpty)
                }
            }
            .alert("Error", isPresented: $duplicateError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("An event with the name '\(name)' already exists.")
            }
        }
    }
    
    private func createEvent() {
        // Check uniqueness within current user's events only
        let userEvents = allEvents.filter { $0.creatorId == authService.currentUser?.id }
        if userEvents.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            duplicateError = true
            return
        }
        
        let creatorName = authService.currentUser?.username ?? "Unknown"
        let creatorId = authService.currentUser?.id
        
        let newEvent = Event(
            name: name, 
            date: date, 
            currencyCode: currencyCode, 
            creatorName: creatorName,
            creatorId: creatorId
        )
        modelContext.insert(newEvent)
        dismiss()
    }
}
