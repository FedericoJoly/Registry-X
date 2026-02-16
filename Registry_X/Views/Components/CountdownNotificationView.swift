import SwiftUI

struct CountdownNotificationView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.blue)
            .cornerRadius(20)
            .shadow(radius: 5)
    }
}
