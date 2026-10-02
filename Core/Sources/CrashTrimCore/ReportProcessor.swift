import Foundation

public struct ProcessingResult: Sendable {
    public let output: String
    public let format: String
    public let maskedOccurrences: Int
    public let removedItems: Int
    public let removedCharacters: Int
    public let recognized: Bool
}

public enum ReportProcessor {
    public static func process(_ input: String, additionalStrings: String = "") throws -> ProcessingResult {
        try Task.checkCancellation()
        let parsed = ReportParser.parse(input)
        let redactor = Redactor(additionalStrings: additionalStrings, original: input)
        var removedItems = 0
        var removedCharacters = 0
        let output: String
        let format: String
        let recognized: Bool
        switch parsed {
        case .json(let objects, let duplicateCharacters):
            for object in objects { redactor.discover(object) }
            // A global discovery pass ensures diagnostics mentioning a sensitive field are covered too.
            redactor.discoverText(input)
            var cleaned: [JSONValue] = []
            for object in objects {
                try Task.checkCancellation()
                cleaned.append(redactor.redactJSON(object, removedItems: &removedItems, removedCharacters: &removedCharacters))
            }
            output = cleaned.map { $0.encoded() }.joined(separator: "\n") + "\n"
            removedCharacters += duplicateCharacters
            if duplicateCharacters > 0 { removedItems += 1 }
            format = objects.count == 2 ? "IPS · JSON 2개" : "충돌 JSON"
            recognized = true
        case .text, .unknown:
            redactor.discoverText(input)
            recognized = if case .text = parsed { true } else { false }
            let trimmed = recognized ? trimText(input, removedItems: &removedItems, removedCharacters: &removedCharacters) : input
            output = redactor.redactText(trimmed)
            format = recognized ? "충돌 리포트 텍스트" : "형식 미인식: 마스킹만 적용"
        }
        try Task.checkCancellation()
        return ProcessingResult(output: output, format: format, maskedOccurrences: redactor.occurrences,
                                removedItems: removedItems, removedCharacters: removedCharacters, recognized: recognized)
    }

    private static func trimText(_ text: String, removedItems: inout Int, removedCharacters: inout Int) -> String {
        let lines = text.components(separatedBy: "\n")
        var kept: [String] = []
        var inHardwareAppendix = false
        var seenBinaryImages = false
        // Only documented non-diagnostic headers are removed. Unknown sections are retained.
        let expendable = #"^\s*(Report Version|Anonymous UUID|Sleep/Wake UUID|Incident Identifier|CrashReporter Key|Beta Identifier|Submission ID)\s*:"#
        for line in lines {
            if line.hasPrefix("Binary Images:") { seenBinaryImages = true }
            if seenBinaryImages && line.range(of: #"^Model:\s*(?:MacBookPro|MacBookAir|MacPro|Macmini|MacStudio|iMacPro|iMac|Mac)\d+,\d+\b"#, options: .regularExpression) != nil {
                inHardwareAppendix = true
            }
            if inHardwareAppendix {
                let hardwareLine = line.isEmpty || line.range(of: #"^(Model|Graphics|Memory Module|AirPort|Bluetooth|Network Service|Serial ATA Device|USB Device|Thunderbolt Bus|Hardware Overview|System Serial Number|Serial Number|Part Number)\s*:"#, options: .regularExpression) != nil
                if !hardwareLine { inHardwareAppendix = false }
                else { removedItems += 1; removedCharacters += line.count + 1; continue }
            }
            if line.range(of: expendable, options: .regularExpression) != nil {
                removedItems += 1; removedCharacters += line.count + 1
            } else { kept.append(line) }
        }
        return kept.joined(separator: "\n")
    }
}
