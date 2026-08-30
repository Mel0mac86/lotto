import Foundation

/// Scrittore ZIP minimale (voci non compresse, metodo `stored`).
///
/// È sufficiente per produrre file `.xlsx` validi: Excel, Numbers e LibreOffice
/// accettano gli archivi senza compressione.
struct ZIPWriter {

    private struct Entry {
        let name: String
        let data: Data
        let crc: UInt32
        let offset: Int
    }

    private var buffer = Data()
    private var entries: [Entry] = []

    mutating func addFile(name: String, contents: Data) {
        let offset = buffer.count
        let crc = ZIPWriter.crc32(contents)
        var header = Data()
        header.appendUInt32(0x04034b50)      // firma local file header
        header.appendUInt16(20)              // versione richiesta
        header.appendUInt16(0)               // flag
        header.appendUInt16(0)               // metodo: stored
        header.appendUInt16(0)               // ora
        header.appendUInt16(0)               // data
        header.appendUInt32(crc)
        header.appendUInt32(UInt32(contents.count))
        header.appendUInt32(UInt32(contents.count))
        let nameData = Data(name.utf8)
        header.appendUInt16(UInt16(nameData.count))
        header.appendUInt16(0)               // extra field
        buffer.append(header)
        buffer.append(nameData)
        buffer.append(contents)
        entries.append(Entry(name: name, data: contents, crc: crc, offset: offset))
    }

    mutating func addFile(name: String, text: String) {
        addFile(name: name, contents: Data(text.utf8))
    }

    func finalize() -> Data {
        var output = buffer
        let directoryOffset = output.count

        for entry in entries {
            var header = Data()
            header.appendUInt32(0x02014b50)  // firma central directory
            header.appendUInt16(20)          // versione di creazione
            header.appendUInt16(20)          // versione richiesta
            header.appendUInt16(0)
            header.appendUInt16(0)           // metodo: stored
            header.appendUInt16(0)
            header.appendUInt16(0)
            header.appendUInt32(entry.crc)
            header.appendUInt32(UInt32(entry.data.count))
            header.appendUInt32(UInt32(entry.data.count))
            let nameData = Data(entry.name.utf8)
            header.appendUInt16(UInt16(nameData.count))
            header.appendUInt16(0)           // extra
            header.appendUInt16(0)           // commento
            header.appendUInt16(0)           // disco
            header.appendUInt16(0)           // attributi interni
            header.appendUInt32(0)           // attributi esterni
            header.appendUInt32(UInt32(entry.offset))
            output.append(header)
            output.append(nameData)
        }

        let directorySize = output.count - directoryOffset
        var end = Data()
        end.appendUInt32(0x06054b50)
        end.appendUInt16(0)
        end.appendUInt16(0)
        end.appendUInt16(UInt16(entries.count))
        end.appendUInt16(UInt16(entries.count))
        end.appendUInt32(UInt32(directorySize))
        end.appendUInt32(UInt32(directoryOffset))
        end.appendUInt16(0)
        output.append(end)
        return output
    }

    /// CRC-32 (polinomio IEEE 802.3), richiesto dal formato ZIP.
    static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) != 0 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
            }
            table[index] = value
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
