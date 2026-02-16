import SwiftUI
import SwiftData

// Enum for Type-Safe Tab Management
enum DashboardTab: String, Identifiable {
    case setup = "Setup"
    case panel = "Panel"
    case registry = "Registry"
    case totals = "Totals"
    
    var id: String { rawValue }
}

struct EventDashboardView: View {
    @Bindable var event: Event
    @Environment(\.dismiss) var dismiss // For quit button
    
    // Tab State
    @State private var selectedTab: DashboardTab = .setup
    @State private var pendingTab: DashboardTab? // Where the user wanted to go
    
    // Interception State
    @State private var isSetupDirty = false
    @State private var showingUnsavedAlert = false
    @State private var triggerSaveSetup = false
    @State private var triggerDiscardSetup = false
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGray6).ignoresSafeArea()
            
            // Intercepting Binding
            let tabBinding = Binding<DashboardTab>(
                get: { selectedTab },
                set: { newValue in
                    if selectedTab == .setup && isSetupDirty && newValue != .setup {
                        // Intercept!
                        pendingTab = newValue
                        showingUnsavedAlert = true
                    } else {
                        // Allow
                        selectedTab = newValue
                    }
                }
            )
            
            TabView(selection: tabBinding) {
                SetupView(
                    event: event,
                    hasUnsavedChanges: $isSetupDirty,
                    triggerSave: $triggerSaveSetup,
                    triggerDiscard: $triggerDiscardSetup
                )
                    .tabItem {
                        Label("Setup", systemImage: "gear")
                    }
                    .tag(DashboardTab.setup)
                    
                PanelView(event: event, onQuit: { dismiss() })
                    .tabItem {
                        Label("Panel", systemImage: "square.grid.2x2")
                    }
                    .tag(DashboardTab.panel)
                
                RegistryView(event: event, onQuit: { dismiss() })
                    .tabItem {
                        Label("Registry", systemImage: "list.bullet")
                    }
                    .tag(DashboardTab.registry)
                
                TotalsView(event: event, onQuit: { dismiss() })
                    .tabItem {
                        Label("Totals", systemImage: "chart.bar")
                    }
                    .tag(DashboardTab.totals)
            }
            .background(Color.blue)
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .alert("Unsaved Changes", isPresented: $showingUnsavedAlert) {
            Button("Discard Changes", role: .destructive) {
                triggerDiscardSetup = true
                if let pending = pendingTab {
                    selectedTab = pending
                    pendingTab = nil
                }
            }
            Button("Save Changes") {
                triggerSaveSetup = true
                // We delay switching slightly to allow SetupView to process the save
                // Depending on sync speed, we might want to wait for isSetupDirty -> false?
                // SetupView sets isSetupDirty = false synchronously after save logic.
                // We can optimistically switch.
                if let pending = pendingTab {
                    selectedTab = pending
                    pendingTab = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingTab = nil
            }
        } message: {
            Text("You have unsaved changes in Setup. Do you want to save them before switching tabs?")
        }
    }
}

