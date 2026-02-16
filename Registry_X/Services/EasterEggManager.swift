import SwiftUI
import Combine

class EasterEggManager: ObservableObject {
    static let shared = EasterEggManager()
    
    @Published var tapCount: Int = 0
    @Published var lastTapTime: Date?
    @Published var showCountdown: Bool = false
    @Published var countdownText: String = ""
    @Published var showPlayer: Bool = false
    @Published var isPlaying: Bool = false
    
    private let audioManager = AudioManager.shared
    private let tapResetInterval: TimeInterval = 1.5
    private let targetTaps: Int = 11
    private var countdownTask: Task<Void, Never>?
    
    private init() {
        // Load audio file - update filename when asset is added
        audioManager.loadAudio(filename: "Outro X")
    }
    
    @MainActor
    func handleTap() {
        let now = Date()
        
        // Reset if too much time passed
        if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) > tapResetInterval {
            tapCount = 0
        }
        
        tapCount += 1
        lastTapTime = now
        
        print("🥚 Easter Egg: Tap #\(tapCount)")
        
        let remaining = targetTaps - tapCount
        
        // Show countdown for every tap from 10 remaining down to 1
        if remaining <= 10 && remaining >= 1 {
            print("🥚 Easter Egg: Showing countdown - \(remaining) remaining")
            
            // Preload audio when countdown reaches 5
            if remaining == 5 && audioManager.audioPlayer == nil {
                audioManager.loadAudio(filename: "Outro X")
                print("🥚 Easter Egg: Preloading audio")
            }
            
            // Cancel previous countdown timer
            countdownTask?.cancel()
            
            showCountdown = true
            countdownText = "\(remaining)"
            
            // Start new timer - hide after 1 second
            countdownTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                // Only hide if this task wasn't cancelled
                if !Task.isCancelled {
                    withAnimation(.easeOut(duration: 0.4)) {
                        showCountdown = false
                    }
                }
            }
        }
        
        // Trigger easter egg
        if tapCount >= targetTaps {
            triggerEasterEgg()
            tapCount = 0
        }
    }
    
    @MainActor
    private func triggerEasterEgg() {
        print("🥚 Easter Egg: TRIGGERED! Showing success message")
        
        // Cancel any running countdown timer from previous taps
        countdownTask?.cancel()
        
        // Ensure audio is loaded (should be preloaded already)
        if audioManager.audioPlayer == nil {
            audioManager.loadAudio(filename: "Outro X")
        }
        
        showCountdown = true
        countdownText = "You found an easter egg!"
        
        // Show player immediately with the message
        showPlayer = true
        audioManager.play()
        isPlaying = true
        
        // Keep success message visible for 3 seconds, then fade it out
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
            print("🥚 Easter Egg: Fading success message")
            
            // Fade out success message while player stays visible
            withAnimation(.easeOut(duration: 0.4)) {
                showCountdown = false
            }
        }
    }
    
    @MainActor
    func togglePlayback() {
        if isPlaying {
            audioManager.pause()
        } else {
            audioManager.play()
        }
        isPlaying.toggle()
    }
    
    @MainActor
    func restart() {
        audioManager.stop()
        audioManager.play()
        isPlaying = true
    }
    
    @MainActor
    func closePlayer() {
        audioManager.stop()
        isPlaying = false
        showPlayer = false
        tapCount = 0
    }
}
