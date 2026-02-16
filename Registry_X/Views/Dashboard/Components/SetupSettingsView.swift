import SwiftUI
import SwiftData

struct SetupSettingsView: View {
    @Binding var draft: DraftEventSettings
    var isLocked: Bool
    
    // Actions from Parent
    var onSave: () -> Void
    var onReset: () -> Void
    var onQuit: () -> Void
    var onRefreshRates: () -> Void
    
    @State private var showingGSheetPlaceholder = false
    
    // Mock States for UI
    @State private var currencies = ["USD", "EUR", "GBP"]
    @State private var editingRateID: UUID? = nil
    
    var body: some View {
        VStack(spacing: 15) {
            
            // CARD 1: MAIN SETTINGS
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
                
                // Main Currency Selector
                VStack(alignment: .leading, spacing: 6) {
                    Text("Main Currency")
                        .font(.body)
                    
                    HStack(spacing: 10) {
                        ForEach(["USD", "EUR", "GBP"], id: \.self) { code in
                            Button(action: { draft.currencyCode = code }) {
                                HStack(spacing: 4) {
                                    Text(currencySymbol(for: code))
                                    Text(code)
                                }
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity)
                                .background(draft.currencyCode == code ? Color.blue : Color(UIColor.systemBackground))
                                .foregroundColor(draft.currencyCode == code ? .white : .primary)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(UIColor.systemGray4), lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                
                // Exchange Rates Table
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Exchange Rates")
                            .font(.body)
                        
                        Spacer()
                        
                        // Refresh Button
                        Button(action: { onRefreshRates() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 10)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        }
                    }
                    .padding(.bottom, 8)
                    
                    // Rates List
                    VStack(spacing: 0) {
                        ForEach($draft.rates) { $rate in
                            VStack(spacing: 0) {
                                HStack {
                                    // Currency Code
                                    Text("\(rate.code):")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 40, alignment: .leading)
                                    
                                    Spacer()
                                    
                                    // Rate Value (Editable or Static)
                                    if rate.code == draft.currencyCode {
                                        // Main Currency is always 1.0 (Locked)
                                        Text("1.0000")
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .monospaced()
                                            .foregroundStyle(.secondary)
                                    } else if editingRateID == rate.id {
                                        // Edit Mode
                                        HStack {
                                            TextField("Rate", value: $rate.rate, format: .number.precision(.fractionLength(2...4)))
                                                .keyboardType(.decimalPad)
                                                .font(.subheadline)
                                                .monospaced()
                                                .multilineTextAlignment(.trailing)
                                                .frame(width: 80)
                                                .textFieldStyle(.roundedBorder)
                                                .onChange(of: rate.rate) {
                                                    $rate.wrappedValue.isManual = true
                                                }
                                            
                                            Button(action: {
                                                rate.isManual = true
                                                editingRateID = nil
                                            }) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                    } else {
                                        // Display Mode
                                        HStack(spacing: 4) {
                                            if rate.isManual {
                                                Image(systemName: "pencil.circle.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.orange)
                                            }
                                            
                                            Text(rate.rate.formatted(.number.precision(.fractionLength(4))))
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                                .monospaced()
                                        }
                                        .onLongPressGesture {
                                            if !isLocked {
                                                editingRateID = rate.id
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 12)
                                
                                if rate.id != draft.rates.last?.id {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                    }
                    .background(Color(UIColor.systemGray6).opacity(0.5))
                    .cornerRadius(10)
                    
                    // Footer
                    if let date = draft.ratesLastUpdated {
                        Text("Last updated: \(date.formatted(date: .numeric, time: .standard))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
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
    
    // Helpers
    func currencySymbol(for code: String) -> String {
        switch code {
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        default: return "$"
        }
    }
}

// Subcomponents
struct ExchangeRateRow: View {
    let code: String
    let rate: String
    
    var body: some View {
        HStack {
            Text("\(code):")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
            
            Spacer()
            
            Text(rate)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospaced()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}

#Preview {
    SetupSettingsViewPreviewWrapper()
}

// Wrapper for Preview State
struct SetupSettingsViewPreviewWrapper: View {
    @State var draft: DraftEventSettings
    
    init() {
        let event = Event(name: "New Event", date: Date(), currencyCode: "EUR")
        // Initialize state with a draft
        _draft = State(initialValue: DraftEventSettings(from: event))
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGray6).ignoresSafeArea()
            ScrollView {
                SetupSettingsView(
                    draft: $draft,
                    isLocked: false,
                    onSave: {},
                    onReset: {},
                    onQuit: {},
                    onRefreshRates: {}
                )
                    .padding(.top, 20)
            }
        }
    }
}

