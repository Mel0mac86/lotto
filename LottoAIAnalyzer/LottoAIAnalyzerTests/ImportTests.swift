import XCTest
@testable import LottoAIAnalyzer

final class CSVImporterTests: XCTestCase {

    func testSemicolonSeparatedImport() throws {
        let csv = """
        data;ruota;numero1;numero2;numero3;numero4;numero5
        03/01/2026;Bari;12;27;44;61;83
        03/01/2026;Napoli;5;19;33;48;77
        """
        let records = try CSVImporter.parse(text: csv, defaultGame: .lotto)

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].wheel, .bari)
        XCTAssertEqual(records[0].numbers, [12, 27, 44, 61, 83])
        XCTAssertEqual(records[1].wheel, .napoli)
    }

    func testCommaSeparatedWithAlternativeHeaders() throws {
        let csv = """
        Data,Ruota,n1,n2,n3,n4,n5
        2026-01-03,BA,1,2,3,4,5
        """
        let records = try CSVImporter.parse(text: csv, defaultGame: .lotto)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].numbers, [1, 2, 3, 4, 5])
        XCTAssertEqual(records[0].wheel, .bari)
    }

    func testSingleNumbersColumn() throws {
        let csv = """
        data;ruota;numeri
        03/01/2026;Roma;7 14 21 28 35
        """
        let records = try CSVImporter.parse(text: csv, defaultGame: .lotto)
        XCTAssertEqual(records[0].numbers, [7, 14, 21, 28, 35])
    }

    func testSuperenalottoWithJollyAndSuperStar() throws {
        let csv = """
        data;numero1;numero2;numero3;numero4;numero5;numero6;jolly;superstar
        2026-01-03;7;18;29;41;56;88;13;42
        """
        let records = try CSVImporter.parse(text: csv, defaultGame: .superenalotto)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].numbers.count, 6)
        XCTAssertEqual(records[0].jolly, 13)
        XCTAssertEqual(records[0].superstar, 42)
        XCTAssertNil(records[0].wheel)
    }

    func testQuotedFieldsAreParsed() {
        let rows = CSVImporter.parseRows(text: "a;\"b;c\";d\n1;2;3", separator: ";")
        XCTAssertEqual(rows.first, ["a", "b;c", "d"])
        XCTAssertEqual(rows.last, ["1", "2", "3"])
    }

    func testRowsWithInvalidNumbersAreSkipped() throws {
        let csv = """
        data;ruota;numero1;numero2;numero3;numero4;numero5
        03/01/2026;Bari;12;27;44;61;83
        03/01/2026;Bari;12;27;44;61
        """
        let records = try CSVImporter.parse(text: csv, defaultGame: .lotto)
        XCTAssertEqual(records.count, 1, "La riga con soli 4 numeri va scartata")
    }

    func testSeparatorDetection() {
        XCTAssertEqual(CSVImporter.detectSeparator(in: "a;b;c\n1;2;3"), ";")
        XCTAssertEqual(CSVImporter.detectSeparator(in: "a,b,c\n1,2,3"), ",")
        XCTAssertEqual(CSVImporter.detectSeparator(in: "a\tb\tc"), "\t")
    }
}

final class JSONImporterTests: XCTestCase {

    func testArrayOfObjects() throws {
        let json = """
        [
          {"data": "2026-01-03", "ruota": "Bari", "numeri": [12, 27, 44, 61, 83]},
          {"data": "2026-01-05", "ruota": "Roma", "numeri": [1, 2, 3, 4, 5]}
        ]
        """
        let records = try JSONImporter.parse(data: Data(json.utf8), defaultGame: .lotto)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].numbers, [12, 27, 44, 61, 83])
    }

    func testWrappedObject() throws {
        let json = """
        {"estrazioni": [{"data": "2026-01-03", "ruota": "Milano", "n1": 3, "n2": 8, "n3": 19, "n4": 42, "n5": 77}]}
        """
        let records = try JSONImporter.parse(data: Data(json.utf8), defaultGame: .lotto)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].wheel, .milano)
        XCTAssertEqual(records[0].numbers, [3, 8, 19, 42, 77])
    }
}

final class DrawParserTests: XCTestCase {

    func testDateFormats() {
        let expected = Calendar.italian.dateComponents([.year, .month, .day],
                                                       from: TestSupport.date("2026-01-03"))
        for candidate in ["2026-01-03", "03/01/2026", "03-01-2026", "03.01.2026"] {
            guard let parsed = DrawParser.parseDate(candidate) else {
                return XCTFail("Formato non riconosciuto: \(candidate)")
            }
            let components = Calendar.italian.dateComponents([.year, .month, .day], from: parsed)
            XCTAssertEqual(components, expected, "Formato \(candidate)")
        }
    }

    func testWheelParsing() {
        XCTAssertEqual(Wheel.parse("Bari"), .bari)
        XCTAssertEqual(Wheel.parse("bari"), .bari)
        XCTAssertEqual(Wheel.parse("BA"), .bari)
        XCTAssertEqual(Wheel.parse("Nazionale"), .nazionale)
        XCTAssertNil(Wheel.parse("Vattelapesca"))
    }

    func testDedupeKeyIgnoresNumberOrder() {
        let date = TestSupport.date("2026-01-03")
        let first = Draw.makeDedupeKey(date: date, game: .lotto, wheel: .bari, numbers: [5, 1, 3, 2, 4])
        let second = Draw.makeDedupeKey(date: date, game: .lotto, wheel: .bari, numbers: [1, 2, 3, 4, 5])
        XCTAssertEqual(first, second)

        let otherWheel = Draw.makeDedupeKey(date: date, game: .lotto, wheel: .roma, numbers: [1, 2, 3, 4, 5])
        XCTAssertNotEqual(first, otherWheel)
    }
}

final class ZIPTests: XCTestCase {

    /// Il file .xlsx prodotto dall'export deve essere rileggibile dall'import.
    func testWriterAndReaderRoundTrip() throws {
        var writer = ZIPWriter()
        writer.addFile(name: "hello.txt", text: "ciao mondo")
        writer.addFile(name: "nested/data.xml", text: "<root>ok</root>")
        let archive = try ZIPArchive(data: writer.finalize())

        XCTAssertEqual(archive.entries.count, 2)
        let first = try archive.extract("hello.txt")
        XCTAssertEqual(first.flatMap { String(data: $0, encoding: .utf8) }, "ciao mondo")
        let second = try archive.extract("nested/data.xml")
        XCTAssertEqual(second.flatMap { String(data: $0, encoding: .utf8) }, "<root>ok</root>")
        XCTAssertNil(try archive.extract("mancante.txt"))
    }

    func testCRC32KnownValue() {
        // CRC-32 di "123456789" è 0xCBF43926.
        XCTAssertEqual(ZIPWriter.crc32(Data("123456789".utf8)), 0xCBF43926)
    }
}
