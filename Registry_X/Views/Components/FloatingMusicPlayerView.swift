import SwiftUI

struct FloatingMusicPlayerView: View {
    @ObservedObject var easterEgg = EasterEggManager.shared
    let albumCoverImage: String
    
    var body: some View {
        VStack(spacing: 16) {
            // Close button
            HStack {
                Spacer()
                Button(action: { easterEgg.closePlayer() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
            }
            
            // Album cover
            if let uiImage = UIImage(named: albumCoverImage) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .cornerRadius(12)
                    .shadow(radius: 8)
                    .onTapGesture {
                        // Open Linktree URL
                        if let url = URL(string: "https://linktr.ee/cicadaxmusic") {
                            UIApplication.shared.open(url)
                        }
                    }
            } else {
                // Placeholder if image not found
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 200, height: 200)
                    
                    Image(systemName: "music.note")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                }
                .shadow(radius: 8)
            }
            
            // Controls
            HStack(spacing: 40) {
                Button(action: { easterEgg.togglePlayback() }) {
                    Image(systemName: easterEgg.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                }
                
                Button(action: { easterEgg.restart() }) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(24)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.3), radius: 20)
        .frame(width: 280)
    }
}
