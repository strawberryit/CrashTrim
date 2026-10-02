import Foundation
import CoreFoundation

// Keep integer spellings intact: converting instruction addresses to Double loses bits.
indirect enum JSONValue: Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String)
    case number(String), bool(Bool), null

    init(_ value: Any) throws {
        switch value {
        case let values as [String: Any]: self = .object(try values.mapValues(JSONValue.init))
        case let values as [Any]: self = .array(try values.map(JSONValue.init))
        case let value as String: self = .string(value)
        case let value as NSNumber:
            self = CFGetTypeID(value) == CFBooleanGetTypeID()
                ? .bool(value.boolValue) : .number(value.stringValue)
        case is NSNull: self = .null
        default: throw CocoaError(.propertyListReadCorrupt)
        }
    }

    func encoded(depth: Int = 0) -> String {
        let indent = String(repeating: "  ", count: depth)
        let child = indent + "  "
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value): return value
        case .string(let value):
            let data = try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
            return String(decoding: data, as: UTF8.self)
        case .array(let values):
            if values.isEmpty { return "[]" }
            return "[\n" + values.map { child + $0.encoded(depth: depth + 1) }.joined(separator: ",\n") + "\n" + indent + "]"
        case .object(let values):
            if values.isEmpty { return "{}" }
            return "{\n" + values.keys.sorted().map {
                child + JSONValue.string($0).encoded() + ": " + values[$0]!.encoded(depth: depth + 1)
            }.joined(separator: ",\n") + "\n" + indent + "}"
        }
    }
}

enum ParsedReport {
    case json([JSONValue], duplicateCharacters: Int)
    case text
    case unknown
}

enum ReportParser {
    static func parse(_ input: String) -> ParsedReport {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        if let objects = jsonObjects(trimmed), isCrash(objects) {
            return .json(objects, duplicateCharacters: 0)
        }
        // The problem-report window can append the complete IPS after a translated view.
        if let marker = input.range(of: #"(?im)^Full Report\s*:\s*\n[- ]*\n?"#, options: .regularExpression),
           input[..<marker.lowerBound].contains("Translated Report"),
           let objects = jsonObjects(String(input[marker.upperBound...])), isCrash(objects) {
            return .json(objects, duplicateCharacters: input.distance(from: input.startIndex, to: marker.upperBound))
        }
        let hasHeader = input.range(of: #"(?m)^(Process|Incident Identifier)\s*:"#, options: .regularExpression) != nil
        let hasFailure = input.range(of: #"(?m)^(Exception Type|Termination Reason|Crashed Thread|Triggered by Thread)\s*:"#, options: .regularExpression) != nil
        return hasHeader && hasFailure ? .text : .unknown
    }

    private static func isCrash(_ objects: [JSONValue]) -> Bool {
        guard objects.count == 1 || objects.count == 2,
              case .object(let body)? = objects.last else { return false }
        return body["threads"] != nil && (body["exception"] != nil || body["termination"] != nil || body["faultingThread"] != nil)
    }

    static func jsonObjects(_ input: String) -> [JSONValue]? {
        var results: [JSONValue] = []
        var start: String.Index?
        var depth = 0
        var quoted = false
        var escaped = false
        for index in input.indices {
            let c = input[index]
            if start == nil {
                if c.isWhitespace || c == "\u{FEFF}" { continue }
                guard c == "{" else { return nil }
                start = index
            }
            if quoted {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { quoted = false }
            } else {
                if c == "\"" { quoted = true }
                else if c == "{" || c == "[" { depth += 1 }
                else if c == "}" || c == "]" { depth -= 1 }
                if depth == 0 {
                    let data = Data(input[start!...index].utf8)
                    guard let object = try? JSONSerialization.jsonObject(with: data),
                          let value = try? JSONValue(object) else { return nil }
                    results.append(value)
                    start = nil
                }
            }
        }
        return start == nil && !results.isEmpty ? results : nil
    }
}
