import SwiftUI
import SwiftData

struct SetupGeneralView: View {
    @Binding var draft: DraftEventSettings
    var isLocked: Bool
    var onCategoryModeChange: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 15) {
            // CARD: GENERAL SETTINGS
            VStack(alignment: .leading, spacing: 30) {
                // Event Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Event Name")
                        .font(.body)
                    
                    TextField("Event Name", text: $draft.name)
                        .font(.body)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(UIColor.systemGray4), lineWidth: 1)
                        )
                }
                
                // Categories Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Categories")
                        .font(.body)
                    
                    // Segmented Control Toggle
                    HStack(spacing: 0) {
                        // Single Option
                        Button(action: {
                            if !isLocked {
                                draft.areCategoriesEnabled = false
                                onCategoryModeChange?()
                            }
                        }) {
                            Text("Single")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(!draft.areCategoriesEnabled ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(!draft.areCategoriesEnabled ? Color.blue : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.borderless)
                        
                        // Multiple Option
                        Button(action: {
                            if !isLocked {
                                draft.areCategoriesEnabled = true
                            }
                        }) {
                            Text("Multiple")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(draft.areCategoriesEnabled ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(draft.areCategoriesEnabled ? Color.blue : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.borderless)
                    }
                    .background(Color(UIColor.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(UIColor.systemGray4), lineWidth: 1)
                    )
                }
                
                // Promos Toggle
                HStack {
                    Text("Promos")
                        .font(.body)
                    
                    Spacer()
                    
                    Toggle("", isOn: $draft.arePromosEnabled)
                        .labelsHidden()
                        .tint(.green)
                        .scaleEffect(0.8)
                }
                .padding(.vertical, 2)
                
                // Total Round-up Toggle
                HStack {
                    Text("Total Round-up")
                        .font(.body)
                    
                    Spacer()
                    
                    Toggle("", isOn: $draft.isTotalRoundUp)
                        .labelsHidden()
                        .tint(.green)
                        .scaleEffect(0.8)
                }
                .padding(.vertical, 2)
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            .disabled(isLocked)
            .opacity(isLocked ? 0.6 : 1.0)
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    SetupGeneralViewPreviewWrapper()
}

// Wrapper for Preview State
struct SetupGeneralViewPreviewWrapper: View {
    @State var draft: DraftEventSettings
    
    init() {
        let event = Event(name: "New Event", date: Date(), currencyCode: "EUR")
        _draft = State(initialValue: DraftEventSettings(from: event))
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGray6).ignoresSafeArea()
            ScrollView {
                SetupGeneralView(
                    draft: $draft,
                    isLocked: false
                )
                    .padding(.top, 20)
            }
        }
    }
}
