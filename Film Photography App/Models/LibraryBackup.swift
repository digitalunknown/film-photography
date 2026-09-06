import Foundation
import UniformTypeIdentifiers

enum LibraryBackupError: LocalizedError {
    case missingLibrary
    case unreadable
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .missingLibrary: "This file isn't an In Camera backup."
        case .unreadable: "Couldn't read this backup."
        case .writeFailed: "Couldn't write the backup file."
        }
    }
}

/// On-device library snapshot: `library.json` plus optional `scans/{rollId}/…`.
enum LibraryBackup {
    static let libraryFileName = "library.json"
    static let scansFolderName = "scans"
    static let fileExtension = "zip"

    static var suggestedFileName: String {
        let stamp = Date.now.formatted(.dateTime.year().month().day())
            .replacingOccurrences(of: "/", with: "-")
        return "In-Camera-Backup-\(stamp).zip"
    }

    static func write(
        payload: PersistedAppData,
        scans: [(rollId: UUID, fileName: String, url: URL)],
        to destination: URL
    ) throws {
        try write(libraryJSON: try DataPersistence.encode(payload), scans: scans, to: destination)
    }

    static func write(
        libraryJSON: Data,
        scans: [(rollId: UUID, fileName: String, url: URL)],
        to destination: URL
    ) throws {
        var files: [(name: String, data: Data)] = []
        files.append((libraryFileName, libraryJSON))

        for scan in scans {
            let name = "\(scansFolderName)/\(scan.rollId.uuidString)/\(scan.fileName)"
            guard let data = try? Data(contentsOf: scan.url), !data.isEmpty else { continue }
            files.append((name, data))
        }

        do {
            try StoreZip.write(files, to: destination)
        } catch {
            throw LibraryBackupError.writeFailed
        }
    }

    static func read(from url: URL) throws -> (payload: PersistedAppData, scansDirectory: URL?) {
        let unpacked = FileManager.default.temporaryDirectory
            .appendingPathComponent("incamera-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)

        if url.pathExtension.lowercased() == "json" {
            let data = try Data(contentsOf: url)
            return (try DataPersistence.decode(data), nil)
        }

        do {
            try StoreZip.extract(url, to: unpacked)
        } catch {
            throw LibraryBackupError.unreadable
        }

        let libraryURL = unpacked.appendingPathComponent(libraryFileName)
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            throw LibraryBackupError.missingLibrary
        }

        let payload: PersistedAppData
        do {
            payload = try DataPersistence.decode(try Data(contentsOf: libraryURL))
        } catch {
            throw LibraryBackupError.unreadable
        }

        let scans = unpacked.appendingPathComponent(scansFolderName)
        let scansDirectory = FileManager.default.fileExists(atPath: scans.path) ? scans : nil
        return (payload, scansDirectory)
    }
}

/// ZIP stored uncompressed. JPEGs don't shrink, and the library JSON is small.
enum StoreZip {
    static func write(_ files: [(name: String, data: Data)], to url: URL) throws {
        var output = Data()
        var centrals: [Data] = []
        var offsets: [UInt32] = []

        for file in files {
            offsets.append(UInt32(output.count))
            let name = Data(file.name.utf8)
            let crc = CRC32.hash(file.data)
            let size = UInt32(file.data.count)

            output.appendUInt32(0x0403_4b50)
            output.appendUInt16(20)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt32(crc)
            output.appendUInt32(size)
            output.appendUInt32(size)
            output.appendUInt16(UInt16(name.count))
            output.appendUInt16(0)
            output.append(name)
            output.append(file.data)

            var central = Data()
            central.appendUInt32(0x0201_4b50)
            central.appendUInt16(20)
            central.appendUInt16(20)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(crc)
            central.appendUInt32(size)
            central.appendUInt32(size)
            central.appendUInt16(UInt16(name.count))
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(0)
            central.appendUInt32(offsets.last ?? 0)
            central.append(name)
            centrals.append(central)
        }

        let cdOffset = UInt32(output.count)
        for central in centrals { output.append(central) }
        let cdSize = UInt32(output.count) - cdOffset

        output.appendUInt32(0x0605_4b50)
        output.appendUInt16(0)
        output.appendUInt16(0)
        output.appendUInt16(UInt16(files.count))
        output.appendUInt16(UInt16(files.count))
        output.appendUInt32(cdSize)
        output.appendUInt32(cdOffset)
        output.appendUInt16(0)

        try output.write(to: url, options: .atomic)
    }

    static func extract(_ zipURL: URL, to directory: URL) throws {
        let data = try Data(contentsOf: zipURL)
        guard data.count >= 22 else { throw LibraryBackupError.unreadable }

        var offset = 0
        while offset + 30 <= data.count {
            let signature = data.uint32(at: offset)
            if signature == 0x0605_4b50 || signature == 0x0201_4b50 { break }
            guard signature == 0x0403_4b50 else { throw LibraryBackupError.unreadable }

            let method = data.uint16(at: offset + 8)
            let compressed = Int(data.uint32(at: offset + 18))
            let nameLength = Int(data.uint16(at: offset + 26))
            let extraLength = Int(data.uint16(at: offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + nameLength
            guard nameEnd + extraLength + compressed <= data.count,
                  method == 0,
                  let name = String(data: data[nameStart..<nameEnd], encoding: .utf8)
            else { throw LibraryBackupError.unreadable }

            let payloadStart = nameEnd + extraLength
            let payload = data[payloadStart..<(payloadStart + compressed)]
            let dest = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(payload).write(to: dest, options: .atomic)
            offset = payloadStart + compressed
        }
    }
}

private enum CRC32 {
    static func hash(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xffff_ffff
    }

    private static let table: [UInt32] = {
        (0..<256).map { index in
            var crc = UInt32(index)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (0xedb8_8320 ^ (crc >> 1)) : (crc >> 1)
            }
            return crc
        }
    }()
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
