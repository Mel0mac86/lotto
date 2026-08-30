import Foundation
import Compression

/// Lettore minimale di archivi ZIP (solo estrazione), sufficiente per i file .xlsx.
///
/// Gestisce le voci memorizzate (`stored`) e quelle compresse con DEFLATE,
/// che sono le uniche usate da Excel e dagli esportatori più diffusi.
struct ZIPArchive {

    struct Entry {
        let name: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    private(set) var entries: [Entry] = []

    init(data: Data) throws {
        self.data = data
        guard let endOffset = Self.findEndOfCentralDirectory(in: data) else {
            throw ImportError.unsupportedFormat("xlsx")
        }
        let entryCount = Int(Self.readUInt16(data, endOffset + 10))
        let directoryOffset = Int(Self.readUInt32(data, endOffset + 16))
        var cursor = directoryOffset

        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count, Self.readUInt32(data, cursor) == 0x02014b50 else { break }
            let method = Self.readUInt16(data, cursor + 10)
            let compressedSize = Int(Self.readUInt32(data, cursor + 20))
            let uncompressedSize = Int(Self.readUInt32(data, cursor + 24))
            let nameLength = Int(Self.readUInt16(data, cursor + 28))
            let extraLength = Int(Self.readUInt16(data, cursor + 30))
            let commentLength = Int(Self.readUInt16(data, cursor + 32))
            let localOffset = Int(Self.readUInt32(data, cursor + 42))
            let nameRange = (cursor + 46)..<(cursor + 46 + nameLength)
            guard nameRange.upperBound <= data.count else { break }
            let name = String(data: data.subdata(in: nameRange), encoding: .utf8) ?? ""
            entries.append(Entry(name: name,
                                 compressionMethod: method,
                                 compressedSize: compressedSize,
                                 uncompressedSize: uncompressedSize,
                                 localHeaderOffset: localOffset))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        guard !entries.isEmpty else { throw ImportError.unsupportedFormat("xlsx") }
    }

    /// Estrae il contenuto di una voce.
    func extract(_ name: String) throws -> Data? {
        guard let entry = entries.first(where: { $0.name == name }) else { return nil }
        let headerOffset = entry.localHeaderOffset
        guard headerOffset + 30 <= data.count, Self.readUInt32(data, headerOffset) == 0x04034b50 else { return nil }
        let nameLength = Int(Self.readUInt16(data, headerOffset + 26))
        let extraLength = Int(Self.readUInt16(data, headerOffset + 28))
        let start = headerOffset + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard end <= data.count else { return nil }
        let payload = data.subdata(in: start..<end)

        switch entry.compressionMethod {
        case 0:
            return payload
        case 8:
            return Self.inflate(payload, expectedSize: entry.uncompressedSize)
        default:
            throw ImportError.unsupportedFormat("zip(\(entry.compressionMethod))")
        }
    }

    // MARK: - Helper binari

    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        // Il commento finale può essere lungo fino a 65535 byte.
        let lowerBound = max(0, data.count - 22 - 65_535)
        var offset = data.count - 22
        while offset >= lowerBound {
            if readUInt32(data, offset) == 0x06054b50 { return offset }
            offset -= 1
        }
        return nil
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        let start = data.startIndex + offset
        return UInt16(data[start]) | (UInt16(data[start + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        let start = data.startIndex + offset
        return UInt32(data[start])
            | (UInt32(data[start + 1]) << 8)
            | (UInt32(data[start + 2]) << 16)
            | (UInt32(data[start + 3]) << 24)
    }

    /// Decompressione DEFLATE grezza tramite il framework Compression.
    static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        let capacity = expectedSize > 0 ? expectedSize : max(data.count * 8, 64 * 1024)
        var output = Data(count: capacity)
        let written: Int = output.withUnsafeMutableBytes { destination -> Int in
            guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { source -> Int in
                guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(destinationBase, capacity,
                                                 sourceBase, data.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return output.prefix(written)
    }
}
