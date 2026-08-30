import Foundation
import UIKit

/// Formati di esportazione supportati.
enum ReportFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf, csv, xlsx

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .pdf: return "PDF"
        case .csv: return "CSV"
        case .xlsx: return "Excel"
        }
    }
    var fileExtension: String { rawValue }
    var icon: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .csv: return "tablecells"
        case .xlsx: return "tablecells.badge.ellipsis"
        }
    }
}

/// Esporta un `ReportDocument` in PDF, CSV o Excel.
@MainActor
enum ReportExporter {

    static func export(_ document: ReportDocument, format: ReportFormat) throws -> URL {
        let data: Data
        switch format {
        case .pdf: data = try pdfData(document)
        case .csv: data = csvData(document)
        case .xlsx: data = xlsxData(document)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(document.fileBaseName).\(format.fileExtension)")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - PDF

    /// Il PDF è generato dall'HTML del report: l'impaginazione automatica di
    /// `UIPrintPageRenderer` gestisce interruzioni di pagina e tabelle lunghe.
    static func pdfData(_ document: ReportDocument) throws -> Data {
        let formatter = UIMarkupTextPrintFormatter(markupText: html(document))
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        // A4 a 72 dpi con margini di 36 punti.
        let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let printable = page.insetBy(dx: 36, dy: 36)
        renderer.setValue(NSValue(cgRect: page), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printable), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for index in 0..<max(renderer.numberOfPages, 1) {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: index, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    static func html(_ document: ReportDocument) -> String {
        var body = """
        <html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, Helvetica, Arial, sans-serif; font-size: 11px; color: #1c1c1e; }
        h1 { font-size: 20px; margin-bottom: 2px; }
        h2 { font-size: 14px; margin-top: 18px; border-bottom: 1px solid #d0d0d5; padding-bottom: 3px; }
        .meta { color: #6c6c70; font-size: 10px; }
        table { width: 100%; border-collapse: collapse; margin-top: 6px; }
        th { background: #f0f0f4; text-align: left; padding: 4px 5px; font-size: 10px; border: 1px solid #d0d0d5; }
        td { padding: 3px 5px; font-size: 10px; border: 1px solid #e2e2e6; }
        .note { color: #6c6c70; font-size: 9px; font-style: italic; margin-top: 4px; }
        .disclaimer { margin-top: 22px; padding: 8px; background: #f7f7fa; border-left: 3px solid #b0b0b8; color: #3a3a3c; font-size: 10px; }
        ul { margin: 4px 0 0 16px; padding: 0; }
        </style></head><body>
        """
        body += "<h1>\(escape(document.title))</h1>"
        body += "<div class=\"meta\">Ambito: \(escape(document.scope))<br>"
        body += "Metodo: \(escape(document.method))<br>"
        body += "Generato il \(Theme.dateFormatter.string(from: document.generatedAt))</div>"

        if !document.summaryLines.isEmpty {
            body += "<h2>Sintesi</h2><ul>"
            for line in document.summaryLines { body += "<li>\(escape(line))</li>" }
            body += "</ul>"
        }

        for table in document.tables {
            body += "<h2>\(escape(table.title))</h2><table><tr>"
            for header in table.headers { body += "<th>\(escape(header))</th>" }
            body += "</tr>"
            for row in table.rows {
                body += "<tr>"
                for cell in row { body += "<td>\(escape(cell))</td>" }
                body += "</tr>"
            }
            body += "</table>"
            if let note = table.note { body += "<div class=\"note\">\(escape(note))</div>" }
        }

        body += "<div class=\"disclaimer\">"
        for disclaimer in document.disclaimers { body += "<p>\(escape(disclaimer))</p>" }
        body += "</div></body></html>"
        return body
    }

    // MARK: - CSV

    static func csvData(_ document: ReportDocument) -> Data {
        var lines: [String] = []
        lines.append(csvRow(["Report", document.title]))
        lines.append(csvRow(["Ambito", document.scope]))
        lines.append(csvRow(["Metodo", document.method]))
        lines.append(csvRow(["Generato il", Theme.dateFormatter.string(from: document.generatedAt)]))
        lines.append("")

        if !document.summaryLines.isEmpty {
            lines.append(csvRow(["Sintesi"]))
            for line in document.summaryLines { lines.append(csvRow([line])) }
            lines.append("")
        }

        for table in document.tables {
            lines.append(csvRow([table.title]))
            lines.append(csvRow(table.headers))
            for row in table.rows { lines.append(csvRow(row)) }
            if let note = table.note { lines.append(csvRow(["Nota", note])) }
            lines.append("")
        }

        for disclaimer in document.disclaimers { lines.append(csvRow([disclaimer])) }
        // BOM UTF-8: Excel apre correttamente gli accenti.
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(lines.joined(separator: "\r\n").utf8))
        return data
    }

    private static func csvRow(_ values: [String]) -> String {
        values.map { value in
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\n", with: " ")
            return "\"\(escaped)\""
        }.joined(separator: ";")
    }

    // MARK: - Excel (.xlsx)

    static func xlsxData(_ document: ReportDocument) -> Data {
        var rows: [[String]] = []
        rows.append([document.title])
        rows.append(["Ambito", document.scope])
        rows.append(["Metodo", document.method])
        rows.append(["Generato il", Theme.dateFormatter.string(from: document.generatedAt)])
        rows.append([])
        for line in document.summaryLines { rows.append([line]) }
        rows.append([])
        for table in document.tables {
            rows.append([table.title])
            rows.append(table.headers)
            rows.append(contentsOf: table.rows)
            if let note = table.note { rows.append(["Nota", note]) }
            rows.append([])
        }
        for disclaimer in document.disclaimers { rows.append([disclaimer]) }

        var writer = ZIPWriter()
        writer.addFile(name: "[Content_Types].xml", text: """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
        """)
        writer.addFile(name: "_rels/.rels", text: """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """)
        writer.addFile(name: "xl/workbook.xml", text: """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="Report" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """)
        writer.addFile(name: "xl/_rels/workbook.xml.rels", text: """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """)

        var sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
        """
        for (rowIndex, row) in rows.enumerated() {
            sheet += "<row r=\"\(rowIndex + 1)\">"
            for (columnIndex, value) in row.enumerated() {
                let reference = "\(columnName(columnIndex))\(rowIndex + 1)"
                // Valori numerici scritti come numeri, il resto come testo inline.
                if let number = Double(value.replacingOccurrences(of: ",", with: ".")),
                   !value.isEmpty, value.rangeOfCharacter(from: CharacterSet.letters) == nil {
                    sheet += "<c r=\"\(reference)\"><v>\(number)</v></c>"
                } else {
                    sheet += "<c r=\"\(reference)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(value))</t></is></c>"
                }
            }
            sheet += "</row>"
        }
        sheet += "</sheetData></worksheet>"
        writer.addFile(name: "xl/worksheets/sheet1.xml", text: sheet)
        return writer.finalize()
    }

    private static func columnName(_ index: Int) -> String {
        var value = index
        var name = ""
        repeat {
            name = String(UnicodeScalar(UInt8(65 + value % 26))) + name
            value = value / 26 - 1
        } while value >= 0
        return name
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
