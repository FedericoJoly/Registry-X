import AVFoundation

class AudioManager {
    static let shared = AudioManager()
    
    var audioPlayer: AVAudioPlayer?
    
    private init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    func loadAudio(filename: String, ext: String = "mp3") {
        guard let url = Bundle.main.url(forResource: filename, withExtension: ext) else {
            print("Audio file not found: \(filename).\(ext)")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
        } catch {
            print("Failed to load audio: \(error)")
        }
    }
    
    func play() {
        audioPlayer?.play()
    }
    
    func pause() {
        audioPlayer?.pause()
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
    }
    
    var isPlaying: Bool {
        audioPlayer?.isPlaying ?? false
    }
}
