import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct JSONFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    let data: Data
    let filename: String
    
    init(data: Data, filename: String) {
        self.data = data
        self.filename = filename
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
        self.filename = configuration.file.filename ?? "event.json"
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}
