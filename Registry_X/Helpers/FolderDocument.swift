import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct FolderDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    
    let url: URL
    
    init(url: URL) {
        self.url = url
    }
    
    init(configuration: ReadConfiguration) throws {
        // Not used for export-only document
        throw CocoaError(.fileReadUnsupportedScheme)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return try FileWrapper(url: url, options: .immediate)
    }
}
