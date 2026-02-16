import SwiftUI

struct SplashView: View {
    @State private var textOpacity: Double = 0.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {

                Image("splash")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height) // Full screen box centers content
                    .clipped()
                    .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    SplashView()
}
