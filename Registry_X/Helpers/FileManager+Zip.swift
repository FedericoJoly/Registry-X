import Foundation
import Compression

extension FileManager {
    /// Creates a ZIP archive from a directory
    /// - Parameters:
    ///   - sourceURL: The directory to zip
    ///   - destinationURL: Where to save the ZIP file
    func zipItem(at sourceURL: URL, to destinationURL: URL) throws {
        // Get all files in the source directory
        let fileURLs = try contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil)
        
        guard !fileURLs.isEmpty else {
            throw NSError(domain: "ZipArchive", code: 1, userInfo: [NSLocalizedDescriptionKey: "No files to archive"])
        }
        
        var zipData = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0
        
        for fileURL in fileURLs {
            let fileName = fileURL.lastPathComponent
            let fileData = try Data(contentsOf: fileURL)
            
            // Local file header
            let localHeader = createLocalFileHeader(fileName: fileName, fileData: fileData)
            let headerOffset = offset
            
            zipData.append(localHeader)
            zipData.append(fileData)
            offset = UInt32(zipData.count)
            
            // Add to central directory
            let centralDirEntry = createCentralDirectoryEntry(
                fileName: fileName,
                fileData: fileData,
                offset: headerOffset
            )
            centralDirectory.append(centralDirEntry)
        }
        
        // Add central directory
        let centralDirOffset = UInt32(zipData.count)
        zipData.append(centralDirectory)
        
        // Add end of central directory record
        let endRecord = createEndOfCentralDirectory(
            entryCount: UInt16(fileURLs.count),
            centralDirSize: UInt32(centralDirectory.count),
            centralDirOffset: centralDirOffset
        )
        zipData.append(endRecord)
        
        // Write to file
        try zipData.write(to: destinationURL)
    }
    
    private func createLocalFileHeader(fileName: String, fileData: Data) -> Data {
        var header = Data()
        
        // Local file header signature
        header.append(contentsOf: [0x50, 0x4b, 0x03, 0x04])
        // Version needed to extract
        header.append(contentsOf: [0x0a, 0x00])
        // General purpose bit flag
        header.append(contentsOf: [0x00, 0x00])
        // Compression method (0 = no compression)
        header.append(contentsOf: [0x00, 0x00])
        // File modification time
        header.append(contentsOf: [0x00, 0x00])
        // File modification date
        header.append(contentsOf: [0x00, 0x00])
        // CRC-32
        let crc = calculateCRC32(data: fileData)
        header.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
        // Compressed size
        header.append(contentsOf: withUnsafeBytes(of: UInt32(fileData.count).littleEndian) { Array($0) })
        // Uncompressed size
        header.append(contentsOf: withUnsafeBytes(of: UInt32(fileData.count).littleEndian) { Array($0) })
        // File name length
        guard let nameData = fileName.data(using: .utf8) else {
            // Fallback to ASCII if UTF-8 fails
            return Data()
        }
        header.append(contentsOf: withUnsafeBytes(of: UInt16(nameData.count).littleEndian) { Array($0) })
        // Extra field length
        header.append(contentsOf: [0x00, 0x00])
        // File name
        header.append(nameData)
        
        return header
    }
    
    private func createCentralDirectoryEntry(fileName: String, fileData: Data, offset: UInt32) -> Data {
        var entry = Data()
        
        // Central directory file header signature
        entry.append(contentsOf: [0x50, 0x4b, 0x01, 0x02])
        // Version made by
        entry.append(contentsOf: [0x0a, 0x00])
        // Version needed to extract
        entry.append(contentsOf: [0x0a, 0x00])
        // General purpose bit flag
        entry.append(contentsOf: [0x00, 0x00])
        // Compression method
        entry.append(contentsOf: [0x00, 0x00])
        // File modification time
        entry.append(contentsOf: [0x00, 0x00])
        // File modification date
        entry.append(contentsOf: [0x00, 0x00])
        // CRC-32
        let crc = calculateCRC32(data: fileData)
        entry.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
        // Compressed size
        entry.append(contentsOf: withUnsafeBytes(of: UInt32(fileData.count).littleEndian) { Array($0) })
        // Uncompressed size
        entry.append(contentsOf: withUnsafeBytes(of: UInt32(fileData.count).littleEndian) { Array($0) })
        // File name length
        guard let nameData = fileName.data(using: .utf8) else {
            // Fallback to ASCII if UTF-8 fails
            return Data()
        }
        entry.append(contentsOf: withUnsafeBytes(of: UInt16(nameData.count).littleEndian) { Array($0) })
        // Extra field length
        entry.append(contentsOf: [0x00, 0x00])
        // File comment length
        entry.append(contentsOf: [0x00, 0x00])
        // Disk number start
        entry.append(contentsOf: [0x00, 0x00])
        // Internal file attributes
        entry.append(contentsOf: [0x00, 0x00])
        // External file attributes
        entry.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        // Relative offset of local header
        entry.append(contentsOf: withUnsafeBytes(of: offset.littleEndian) { Array($0) })
        // File name
        entry.append(nameData)
        
        return entry
    }
    
    private func createEndOfCentralDirectory(entryCount: UInt16, centralDirSize: UInt32, centralDirOffset: UInt32) -> Data {
        var record = Data()
        
        // End of central directory signature
        record.append(contentsOf: [0x50, 0x4b, 0x05, 0x06])
        // Number of this disk
        record.append(contentsOf: [0x00, 0x00])
        // Disk where central directory starts
        record.append(contentsOf: [0x00, 0x00])
        // Number of central directory records on this disk
        record.append(contentsOf: withUnsafeBytes(of: entryCount.littleEndian) { Array($0) })
        // Total number of central directory records
        record.append(contentsOf: withUnsafeBytes(of: entryCount.littleEndian) { Array($0) })
        // Size of central directory
        record.append(contentsOf: withUnsafeBytes(of: centralDirSize.littleEndian) { Array($0) })
        // Offset of start of central directory
        record.append(contentsOf: withUnsafeBytes(of: centralDirOffset.littleEndian) { Array($0) })
        // ZIP file comment length
        record.append(contentsOf: [0x00, 0x00])
        
        return record
    }
    
    private func calculateCRC32(data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = (crc >> 8) ^ crc32Table[index]
        }
        
        return crc ^ 0xffffffff
    }
    
    // CRC-32 lookup table
    private var crc32Table: [UInt32] {
        (0..<256).map { i -> UInt32 in
            var crc = UInt32(i)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xedb88320
                } else {
                    crc = crc >> 1
                }
            }
            return crc
        }
    }
}

