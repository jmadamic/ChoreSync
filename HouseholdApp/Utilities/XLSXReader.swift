// XLSXReader.swift
// Minimal .xlsx reader: enough to pull cell values out of a workbook
// exported by Excel, Google Sheets, or Numbers — used by the meal-plan
// importer.
//
// An .xlsx file is a zip archive of XML parts. Foundation has no zip API,
// but zip entries are raw DEFLATE streams and Apple's Compression framework
// decodes raw DEFLATE (COMPRESSION_ZLIB), so a ~100-line central-directory
// reader avoids pulling in a third-party dependency for a single feature.
//
// Deliberately unsupported: zip64, encryption, formulas (only their cached
// values), cell styles other than "is this a number". That covers every
// file a spreadsheet app produces for a template this size.

import Foundation
import Compression

enum XLSXError: LocalizedError {
    case notAZip
    case unsupportedCompression(String)
    case inflateFailed(String)
    case missingPart(String)
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .notAZip:                        return "That file isn't an .xlsx spreadsheet."
        case .unsupportedCompression(let n):  return "Unsupported compression in \(n)."
        case .inflateFailed(let n):           return "Couldn't decompress \(n)."
        case .missingPart(let n):             return "The spreadsheet is missing \(n) — re-save it as .xlsx and try again."
        case .malformed(let what):            return "The spreadsheet couldn't be read (\(what))."
        }
    }
}

/// One cell's value. Numbers are kept numeric so date serials can be told
/// apart from typed text like "Sep 14".
enum XLSXCell: Equatable {
    case text(String)
    case number(Double)
    case bool(Bool)

    var stringValue: String {
        switch self {
        case .text(let s):   return s
        case .number(let d):
            // Whole numbers print without ".0" so quantities read naturally.
            return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
        case .bool(let b):   return b ? "TRUE" : "FALSE"
        }
    }

    var isBlank: Bool {
        if case .text(let s) = self { return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return false
    }
}

/// A sheet as a sparse grid: `rows[r][c]` (0-based). Missing cells are nil.
struct XLSXSheet {
    let name: String
    let rows: [[XLSXCell?]]

    func cell(_ row: Int, _ col: Int) -> XLSXCell? {
        guard row < rows.count, col < rows[row].count else { return nil }
        return rows[row][col]
    }
}

struct XLSXWorkbook {
    let sheets: [XLSXSheet]

    /// Case/space-insensitive lookup: "meals", "Meals ", "MEALS" all match.
    func sheet(named name: String) -> XLSXSheet? {
        let key = XLSXWorkbook.normalize(name)
        return sheets.first { XLSXWorkbook.normalize($0.name) == key }
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

// MARK: - Reader

enum XLSXReader {

    static func read(_ data: Data) throws -> XLSXWorkbook {
        let entries = try ZipArchive.entries(in: data)
        func part(_ path: String) throws -> Data {
            let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
            guard let entry = entries[clean] else { throw XLSXError.missingPart(clean) }
            return try ZipArchive.extract(entry, from: data)
        }

        let shared = try SharedStringsParser.parse(try? part("xl/sharedStrings.xml"))
        let sheetsMeta = try WorkbookParser.parse(try part("xl/workbook.xml"))
        let rels = try RelsParser.parse(try part("xl/_rels/workbook.xml.rels"))

        var sheets: [XLSXSheet] = []
        for meta in sheetsMeta {
            guard let target = rels[meta.rId] else { continue }
            let path = target.hasPrefix("/") ? String(target.dropFirst())
                     : (target.hasPrefix("xl/") ? target : "xl/" + target)
            let rows = try SheetParser.parse(try part(path), shared: shared)
            sheets.append(XLSXSheet(name: meta.name, rows: rows))
        }
        guard !sheets.isEmpty else { throw XLSXError.malformed("no sheets") }
        return XLSXWorkbook(sheets: sheets)
    }
}

// MARK: - Zip

private struct ZipEntry {
    let name: String
    let method: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
}

private enum ZipArchive {

    static func entries(in data: Data) throws -> [String: ZipEntry] {
        let bytes = [UInt8](data)
        let count = bytes.count
        guard count > 22 else { throw XLSXError.notAZip }

        // End-of-central-directory record: scan backwards for its signature
        // (a trailing comment can push it up to 64 KB from the end).
        let minStart = max(0, count - 22 - 65_535)
        var eocd = -1
        var i = count - 22
        while i >= minStart {
            if bytes[i] == 0x50, bytes[i+1] == 0x4B, bytes[i+2] == 0x05, bytes[i+3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw XLSXError.notAZip }

        let total    = Int(u16(bytes, eocd + 10))
        let cdOffset = Int(u32(bytes, eocd + 16))
        guard cdOffset < count else { throw XLSXError.malformed("central directory offset") }

        var result: [String: ZipEntry] = [:]
        var p = cdOffset
        for _ in 0..<total {
            guard p + 46 <= count,
                  bytes[p] == 0x50, bytes[p+1] == 0x4B, bytes[p+2] == 0x01, bytes[p+3] == 0x02
            else { throw XLSXError.malformed("central directory entry") }
            let method   = u16(bytes, p + 10)
            let compSize = Int(u32(bytes, p + 20))
            let rawSize  = Int(u32(bytes, p + 24))
            let nameLen  = Int(u16(bytes, p + 28))
            let extraLen = Int(u16(bytes, p + 30))
            let commLen  = Int(u16(bytes, p + 32))
            let local    = Int(u32(bytes, p + 42))
            guard p + 46 + nameLen <= count else { throw XLSXError.malformed("entry name") }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            result[name] = ZipEntry(name: name, method: method, compressedSize: compSize,
                                    uncompressedSize: rawSize, localHeaderOffset: local)
            p += 46 + nameLen + extraLen + commLen
        }
        return result
    }

    static func extract(_ entry: ZipEntry, from data: Data) throws -> Data {
        let bytes = [UInt8](data)
        let h = entry.localHeaderOffset
        guard h + 30 <= bytes.count,
              bytes[h] == 0x50, bytes[h+1] == 0x4B, bytes[h+2] == 0x03, bytes[h+3] == 0x04
        else { throw XLSXError.malformed("local header for \(entry.name)") }
        let nameLen  = Int(u16(bytes, h + 26))
        let extraLen = Int(u16(bytes, h + 28))
        let start = h + 30 + nameLen + extraLen
        let end = start + entry.compressedSize
        guard end <= bytes.count else { throw XLSXError.malformed("data range for \(entry.name)") }
        let compressed = Array(bytes[start..<end])

        switch entry.method {
        case 0:
            return Data(compressed)
        case 8:
            guard entry.uncompressedSize > 0 else { return Data() }
            var dst = [UInt8](repeating: 0, count: entry.uncompressedSize)
            let written = compressed.withUnsafeBufferPointer { src in
                dst.withUnsafeMutableBufferPointer { dstBuf in
                    compression_decode_buffer(dstBuf.baseAddress!, entry.uncompressedSize,
                                              src.baseAddress!, compressed.count,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            guard written == entry.uncompressedSize else { throw XLSXError.inflateFailed(entry.name) }
            return Data(dst)
        default:
            throw XLSXError.unsupportedCompression(entry.name)
        }
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) | (UInt16(b[i+1]) << 8)
    }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | (UInt32(b[i+1]) << 8) | (UInt32(b[i+2]) << 16) | (UInt32(b[i+3]) << 24)
    }
}

// MARK: - XML parts

/// workbook.xml → ordered (sheet name, relationship id).
private final class WorkbookParser: NSObject, XMLParserDelegate {
    struct Meta { let name: String; let rId: String }
    private var sheets: [Meta] = []

    static func parse(_ data: Data) throws -> [Meta] {
        let p = WorkbookParser()
        let parser = XMLParser(data: data)
        parser.delegate = p
        guard parser.parse() else { throw XLSXError.malformed("workbook.xml") }
        return p.sheets
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        guard name == "sheet" || name.hasSuffix(":sheet") else { return }
        let rId = attributes["r:id"] ?? attributes.first { $0.key.hasSuffix(":id") }?.value ?? ""
        sheets.append(Meta(name: attributes["name"] ?? "Sheet", rId: rId))
    }
}

/// workbook.xml.rels → rId → target path.
private final class RelsParser: NSObject, XMLParserDelegate {
    private var map: [String: String] = [:]

    static func parse(_ data: Data) throws -> [String: String] {
        let p = RelsParser()
        let parser = XMLParser(data: data)
        parser.delegate = p
        guard parser.parse() else { throw XLSXError.malformed("workbook.xml.rels") }
        return p.map
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        guard name == "Relationship", let id = attributes["Id"], let target = attributes["Target"] else { return }
        map[id] = target
    }
}

/// sharedStrings.xml → index → string (rich-text runs concatenated).
private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var inSI = false
    private var inT = false

    static func parse(_ data: Data?) throws -> [String] {
        guard let data else { return [] }
        let p = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = p
        guard parser.parse() else { throw XLSXError.malformed("sharedStrings.xml") }
        return p.strings
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        if name == "si" { inSI = true; current = "" }
        else if name == "t", inSI { inT = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inT { current += string }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "t" { inT = false }
        else if name == "si" { strings.append(current); inSI = false }
    }
}

/// One worksheet → sparse grid of cells.
private final class SheetParser: NSObject, XMLParserDelegate {
    private let shared: [String]
    private var rows: [[XLSXCell?]] = []

    private var currentRow = -1
    private var currentCol = -1
    private var cellType = ""
    private var buffer = ""
    private var inV = false
    private var inIS_T = false
    private var inIS = false

    init(shared: [String]) { self.shared = shared }

    static func parse(_ data: Data, shared: [String]) throws -> [[XLSXCell?]] {
        let p = SheetParser(shared: shared)
        let parser = XMLParser(data: data)
        parser.delegate = p
        guard parser.parse() else { throw XLSXError.malformed("worksheet") }
        return p.rows
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        switch name {
        case "row":
            if let r = attributes["r"], let n = Int(r) { currentRow = n - 1 } else { currentRow += 1 }
            currentCol = -1
        case "c":
            if let ref = attributes["r"], let (r, c) = SheetParser.parseRef(ref) {
                currentRow = r; currentCol = c
            } else {
                currentCol += 1
            }
            cellType = attributes["t"] ?? ""
            buffer = ""
        case "v":
            inV = true; buffer = ""
        case "is":
            inIS = true; buffer = ""
        case "t" where inIS:
            inIS_T = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inV || inIS_T { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "v":
            inV = false
            store(valueFor(buffer))
        case "t" where inIS:
            inIS_T = false
        case "is":
            inIS = false
            store(.text(buffer))
        default: break
        }
    }

    private func valueFor(_ raw: String) -> XLSXCell {
        switch cellType {
        case "s":
            if let i = Int(raw), i < shared.count { return .text(shared[i]) }
            return .text("")
        case "b":
            return .bool(raw == "1")
        case "str", "inlineStr":
            return .text(raw)
        default:
            if let d = Double(raw) { return .number(d) }
            return .text(raw)
        }
    }

    private func store(_ cell: XLSXCell) {
        guard currentRow >= 0, currentCol >= 0 else { return }
        while rows.count <= currentRow { rows.append([]) }
        while rows[currentRow].count <= currentCol { rows[currentRow].append(nil) }
        rows[currentRow][currentCol] = cell
    }

    /// "B7" → (row 6, col 1).
    static func parseRef(_ ref: String) -> (Int, Int)? {
        var col = 0
        var digits = ""
        for ch in ref {
            if ch.isLetter, let a = ch.uppercased().unicodeScalars.first?.value {
                col = col * 26 + Int(a - 64)
            } else if ch.isNumber {
                digits.append(ch)
            }
        }
        guard col > 0, let row = Int(digits), row > 0 else { return nil }
        return (row - 1, col - 1)
    }
}
