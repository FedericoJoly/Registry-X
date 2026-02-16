import SwiftUI
import UIKit

// UIActivityViewController wrapper for SwiftUI
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let fileName: String?
    
    init(activityItems: [Any], fileName: String? = nil) {
        self.activityItems = activityItems
        self.fileName = fileName
    }
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Create a temporary file for the JSON data if needed
        var items: [Any] = []
        
        for item in activityItems {
            if let data = item as? Data, let fileName = fileName {
                // Write to temp file
                let tempDir = FileManager.default.temporaryDirectory
                let fileURL = tempDir.appendingPathComponent(fileName)
                
                do {
                    try data.write(to: fileURL)
                    items.append(fileURL)
                } catch {
                    print("Error writing file: \(error)")
                    items.append(data)
                }
            } else {
                items.append(item)
            }
        }
        
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}
