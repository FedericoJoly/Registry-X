import SwiftUI

struct EventInfoHeader: View {
    let event: Event
    let userFullName: String
    var onQuit: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            // Quit Button (Moved to left for iOS UX alignment)
            if let quitAction = onQuit {
                Button(action: quitAction) {
                    Image(systemName: "door.left.hand.open")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
                .padding(.trailing, 12)
            }
            
            // Event Name
            VStack(alignment: .leading) {
                Text(event.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            
            Spacer()
            
            // User Name
            VStack(alignment: .center) {
                Text(userFullName)
                    .font(.headline) // Fixed: Now matches Event/Currency size
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            // Currency
            VStack(alignment: .trailing) {
                Text(event.currencyCode)
                    .font(.headline)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    let event = Event(name: "Test Event", date: Date(), currencyCode: "USD")
    EventInfoHeader(event: event, userFullName: "John Doe", onQuit: {})
}
