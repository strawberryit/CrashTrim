import Foundation

/// A report-scoped redactor. Original values never leave this object or get persisted.
final class Redactor {
    private struct Replacement {
        let value: String
        let token: String
        let literal: Bool
    }
    private var replacements: [String: Replacement] = [:]
    private var counters: [String: Int] = [:]
    private var reservedTokens: Set<String> = []
    private var numericAliases: [String: String] = [:]
    private var originalNumbers: Set<String> = []
    private var numericCount = 0
    private var sortedReplacements: [Replacement]?
    private(set) var occurrences = 0

    private static let removedKeys: Set<String> = [
        "incident", "incidentid", "incidentidentifier", "crashreporterkey", "betaidentifier",
        "submissionid", "reportversion", "reportertype", "isfirstparty", "sharewithappdevs"
    ]
    private static let numericKeys: Set<String> = [
        "pid", "ppid", "parentpid", "procid", "userid", "uid", "responsiblepid", "bypid", "coalitionid", "coalition", "asid"
    ]
    private static let numericPatterns = [
        #"(?im)^\s*(?:User ID|PID|Parent PID|Responsible PID|Coalition ID)\s*:\s*(\d+)"#,
        #"(?im)^\s*(?:Process|Parent Process|Responsible|Coalition)\s*:.*?\[(\d+)\]"#,
        #"(?i)\bpid\s*[:= ]\s*(\d+)"#,
        #"(?i)\"(?:pid|ppid|parentPid|userID|uid|responsiblePid|byPid|coalitionID|coalition|asid)\"\s*:\s*\"?(\d+)"#
    ]

    init(additionalStrings: String, original: String) {
        for match in matches(#"\[[A-Z]+_\d+\]"#, in: original) {
            reservedTokens.insert((original as NSString).substring(with: match.range))
        }
        let values = additionalStrings.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.count > $1.count }
        for value in values { register(value, kind: "CUSTOM", literal: true) }
    }

    private static func normalized(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func kind(for key: String) -> String? {
        let key = normalized(key)
        if ["serial", "serialnumber", "systemserialnumber", "deviceserialnumber", "serialno", "sn"].contains(key) || key.hasSuffix("serialnumber") { return "SERIAL" }
        if ["partnumber", "partno", "pn", "boardid", "logicboardid", "mlb"].contains(key) || key.hasSuffix("partnumber") { return "PART" }
        if key.contains("uuid") || ["incident", "incidentid", "incidentidentifier", "crashreporterkey", "betaidentifier", "deviceid", "hardwareid", "udid", "reportid"].contains(key) { return "UUID" }
        if ["username", "user", "account", "accountname", "fullname", "realname", "computername", "ownername"].contains(key) { return "USER" }
        if ["hostname", "host", "machinename", "localhostname"].contains(key) { return "HOST" }
        if key.contains("email") { return "EMAIL" }
        if ["macaddress", "ipaddress", "ipv4address", "ipv6address", "networkaddress", "bssid", "ssid"].contains(key) { return "NETWORK" }
        if ["model", "modelcode", "hardwaremodel", "devicemodel", "machinemodel", "modelidentifier"].contains(key) { return "MODEL" }
        if ["appname", "procname", "process", "parentproc", "parentprocess", "responsible", "responsibleproc", "coalitionname", "coalition", "identifier", "bundleid", "bundleidentifier", "cfbundleidentifier", "cfbundlename", "cfbundledisplayname", "codesigningid", "codesigningteamid", "teamid"].contains(key) { return "APP" }
        if ["timestamp", "capturetime", "proclaunch", "datetime", "launchtime", "date", "time"].contains(key) { return "TIME" }
        return nil
    }

    @discardableResult
    private func register(_ value: String, kind: String, literal: Bool = false) -> String {
        guard !value.isEmpty else { return value }
        if let existing = replacements[value] { return existing.token }
        var token: String
        repeat {
            counters[kind, default: 0] += 1
            token = "[\(kind)_\(counters[kind]!)]"
        } while reservedTokens.contains(token) || token == value
        reservedTokens.insert(token)
        replacements[value] = Replacement(value: value, token: token, literal: literal)
        sortedReplacements = nil
        return token
    }

    func discover(_ value: JSONValue, context: String = "") {
        guard !Task.isCancelled else { return }
        switch value {
        case .object(let object):
            for key in object.keys.sorted() {
                let value = object[key]!
                if case .string(let string) = value {
                    if let kind = Self.kind(for: key) { register(string, kind: kind) }
                    if Self.numericKeys.contains(Self.normalized(key)), string.allSatisfy(\.isNumber) { originalNumbers.insert(string) }
                    if Self.normalized(key).contains("path") { discoverPath(string) }
                    if Self.normalized(key) == "name", context == "usedimages",
                       case .string(let path) = object["path"], !isSystemPath(path) {
                        register(string, kind: "APP")
                    }
                }
                discover(value, context: Self.normalized(key))
            }
        case .array(let values): for value in values { discover(value, context: context) }
        case .number(let number):
            if Self.numericKeys.contains(context) { originalNumbers.insert(number) }
        case .string(let string):
            if !context.contains("version") { discoverFreeText(string) }
        default: break
        }
    }

    func discoverText(_ input: String) {
        guard !Task.isCancelled else { return }
        for pattern in Self.numericPatterns {
            for match in matches(pattern, in: input) { originalNumbers.insert((input as NSString).substring(with: match.range(at: 1))) }
        }
        if let objects = ReportParser.jsonObjects(input) {
            for object in objects { discover(object) }
        }
        // Even a damaged JSON report must have recognizable sensitive string fields masked.
        let quotedField = #"\"([^\"\r\n]+)\"\s*:\s*(\"(?:\\.|[^\"\\])*\")"#
        for match in matches(quotedField, in: input) {
            let ns = input as NSString
            let key = ns.substring(with: match.range(at: 1))
            let fragment = ns.substring(with: match.range(at: 2))
            if let data = fragment.data(using: .utf8),
               let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String {
                if let kind = Self.kind(for: key) { register(value, kind: kind) }
                if Self.normalized(key).contains("path") { discoverPath(value) }
                // Fallback text may contain escaped JSON strings, even if the report is damaged.
                let raw = String(fragment.dropFirst().dropLast())
                if raw != value, let replacement = replacements[value] {
                    replacements[raw] = Replacement(value: raw, token: replacement.token, literal: replacement.literal)
                    sortedReplacements = nil
                }
            }
        }
        let labelPattern = #"(?im)^\s*([A-Za-z][A-Za-z0-9 /_.-]{0,70})\s*:\s*(.*)$"#
        for match in matches(labelPattern, in: input) {
            if Task.isCancelled { return }
            let ns = input as NSString
            let label = ns.substring(with: match.range(at: 1))
            var value = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let kind = Self.kind(for: label), !value.isEmpty else { continue }
            if kind == "APP" {
                // PID suffix is separate from the executable name.
                value = value.replacingOccurrences(of: #"\s*\[\d+\]\s*$"#, with: "", options: .regularExpression)
            }
            register(value, kind: kind)
        }
        // Serial/part fields also occur inside hardware-inventory lines and quoted diagnostics.
        let embedded = #"(?i)\b(serial(?:\s*(?:number|no\.?))?|part\s*(?:number|no\.?)|S/N|P/N)\s*[:=]\s*[\"']?([A-Za-z0-9][A-Za-z0-9._/-]*)"#
        for match in matches(embedded, in: input) {
            let ns = input as NSString
            let label = ns.substring(with: match.range(at: 1))
            register(ns.substring(with: match.range(at: 2)), kind: label.lowercased().hasPrefix("p") ? "PART" : "SERIAL")
        }
        discoverFreeText(input)
    }

    private func discoverFreeText(_ text: String) {
        let patterns: [(String, String)] = [
            (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "EMAIL"),
            (#"(?i)(?<![A-F0-9])[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}(?![A-F0-9])"#, "UUID"),
            (#"(?i)(?<![A-F0-9])[A-F0-9]{32}(?![A-F0-9])"#, "UUID"),
            (#"(?i)(?<![A-F0-9:])(?:[A-F0-9]{2}[:-]){5}[A-F0-9]{2}(?![A-F0-9:])"#, "NETWORK"),
            (#"(?<![\w.])(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?![\w.])"#, "NETWORK"),
            (#"(?i)(?<![\w:])(?:[a-f0-9]{1,4}:){2,}[a-f0-9:]{0,39}(?:%[\w]+)?(?![\w:])"#, "NETWORK"),
            (#"(?i)(?<![\w:])(?:[a-f0-9]{1,4})?::(?:[a-f0-9]{1,4}:)*[a-f0-9]{0,4}(?:%[\w]+)?(?![\w:])"#, "NETWORK"),
            (#"(?i)\b[A-Z0-9][A-Z0-9_-]*(?:\.[A-Z0-9_-]+)*\.local\b"#, "HOST"),
            (#"\b(?:MacBookPro|MacBookAir|MacPro|Macmini|MacStudio|iMacPro|iMac|Mac)\d+,\d+\b"#, "MODEL"),
            (#"\b\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:\s*(?:Z|[+-]\d{2}:?\d{2}))?"#, "TIME")
        ]
        for (pattern, kind) in patterns {
            if Task.isCancelled { return }
            for match in matches(pattern, in: text) {
                let ns = text as NSString
                register(ns.substring(with: match.range), kind: kind)
            }
        }
        // Values of path fields can contain spaces; quoted paths and complete path lines take precedence.
        let pathPatterns = [
            #"(?m)^\s*(?:Path|Executable Path|procPath|path)\s*:\s*(/[^\r\n]+)"#,
            #"[\"'](/[^\"'\r\n]+)[\"']"#,
            #"(/(?:Users|Volumes|opt|home|Library|private/(?:var|tmp)|var/(?:folders|tmp)|tmp)/[^\"'<>\r\n,;]*)"#,
            #"(?<![\w])(~(?:[A-Za-z0-9_-]+)?/[^\"'<>\r\n,;]*)"#
        ]
        for pattern in pathPatterns {
            for match in matches(pattern, in: text) {
                discoverPath((text as NSString).substring(with: match.range(at: 1)))
            }
        }
        if (text.hasPrefix("/") || text.hasPrefix("~/")), !text.contains("\n") { discoverPath(text) }
    }

    private func isSystemPath(_ path: String) -> Bool {
        ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/"].contains { path.hasPrefix($0) }
    }

    private func discoverPath(_ path: String) {
        guard path.hasPrefix("/") || path.hasPrefix("~") else { return }
        if isSystemPath(path) { return }
        if let appRange = path.range(of: ".app/"), !path.hasPrefix("/Volumes/") {
            let prefix = String(path[..<appRange.lowerBound])
            let appName = (prefix as NSString).lastPathComponent
            register(appName, kind: "APP")
            if let userMatch = matches(#"^/Users/([^/]+)"#, in: path).first {
                register((path as NSString).substring(with: userMatch.range(at: 1)), kind: "USER")
            }
            // Any directories above the app may themselves identify a project or person.
            if !path.hasPrefix("/Applications/") && !path.hasPrefix("/System/") {
                let parent = (prefix as NSString).deletingLastPathComponent
                register(parent, kind: "PATH")
            }
        } else {
            register(path, kind: "PATH")
            if let match = matches(#"^/Users/([^/]+)"#, in: path).first {
                register((path as NSString).substring(with: match.range(at: 1)), kind: "USER")
            }
        }
    }

    func redactJSON(_ value: JSONValue, key: String = "", removedItems: inout Int, removedCharacters: inout Int) -> JSONValue {
        switch value {
        case .object(let object):
            var result: [String: JSONValue] = [:]
            for name in object.keys.sorted() {
                let value = object[name]!
                if Self.removedKeys.contains(Self.normalized(name)) {
                    removedItems += 1; removedCharacters += name.count + value.encoded().count
                } else {
                    // Additional literals also cover otherwise-unrecognized dynamic JSON keys.
                    var outputName = redactText(name, customOnly: true)
                    while result[outputName] != nil { outputName += "_" }
                    result[outputName] = redactJSON(value, key: name, removedItems: &removedItems, removedCharacters: &removedCharacters)
                }
            }
            return .object(result)
        case .array(let values):
            return .array(values.map { redactJSON($0, key: key, removedItems: &removedItems, removedCharacters: &removedCharacters) })
        case .string(let string):
            if Self.numericKeys.contains(Self.normalized(key)), !string.isEmpty, string.allSatisfy(\.isNumber) {
                occurrences += 1
                return .string(numericAlias(string))
            }
            if Self.normalized(key).contains("path") { discoverPath(string) }
            return .string(redactText(string, preserveNetwork: Self.normalized(key).contains("version")))
        case .number(let number):
            if Self.numericKeys.contains(Self.normalized(key)) {
                occurrences += 1
                return .number(numericAlias(number))
            }
            // A literal matching the entire number must preserve its JSON type.
            if replacements[number]?.literal == true {
                occurrences += 1
                return .number(numericAlias(number))
            }
            return value
        default: return value
        }
    }

    private func numericAlias(_ original: String) -> String {
        if let alias = numericAliases[original] { return alias }
        var alias: String
        repeat {
            numericCount += 1
            alias = String(900_000 + numericCount)
        } while originalNumbers.contains(alias) || alias == original
        numericAliases[original] = alias
        return alias
    }

    func redactText(_ input: String, customOnly: Bool = false, preserveNetwork: Bool = false) -> String {
        if sortedReplacements == nil {
            sortedReplacements = replacements.values.sorted {
                if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
                return $0.value < $1.value
            }
        }
        let ns = input as NSString
        var edits: [(NSRange, String)] = []
        var occupied = IndexSet()
        let versionRanges = (
            matches(#"(?im)^\s*(?:Version|OS Version|App Version|Application Version)\s*:[^\r\n]*"#, in: input) +
            matches(#"(?i)\"[^\"]*version[^\"]*\"\s*:\s*\"(?:\\.|[^\"\\])*\""#, in: input)
        ).map(\.range)
        // Select all edits against the original, never re-process generated placeholder tokens.
        for replacement in sortedReplacements! {
            if Task.isCancelled { return "" }
            if customOnly && !replacement.literal { continue }
            let isAutomaticNetwork = replacement.token.hasPrefix("[NETWORK_") && !replacement.literal
            if preserveNetwork && isAutomaticNetwork { continue }
            var location = 0
            while location < ns.length {
                if Task.isCancelled { return "" }
                let range = ns.range(of: replacement.value, options: [], range: NSRange(location: location, length: ns.length - location))
                if range.location == NSNotFound { break }
                location = NSMaxRange(range)
                if isAutomaticNetwork && versionRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) { continue }
                if !replacement.literal && !hasTokenBoundaries(ns, range: range, value: replacement.value) { continue }
                let occupiedRange = range.location..<NSMaxRange(range)
                if occupied.intersects(integersIn: occupiedRange) { continue }
                edits.append((range, replacement.token))
                occupied.insert(integersIn: occupiedRange)
            }
        }
        for pattern in Self.numericPatterns {
            if customOnly { break }
            for match in matches(pattern, in: input) {
                let range = match.range(at: 1)
                let occupiedRange = range.location..<NSMaxRange(range)
                if !occupied.intersects(integersIn: occupiedRange) {
                    edits.append((range, numericAlias(ns.substring(with: range))))
                    occupied.insert(integersIn: occupiedRange)
                }
            }
        }
        var result = ""
        result.reserveCapacity(input.utf8.count)
        var cursor = 0
        for (range, value) in edits.sorted(by: { $0.0.location < $1.0.location }) {
            if Task.isCancelled { return "" }
            result += ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
            result += value
            cursor = NSMaxRange(range)
        }
        result += ns.substring(from: cursor)
        occurrences += edits.count
        return result
    }

    private func hasTokenBoundaries(_ input: NSString, range: NSRange, value: String) -> Bool {
        let word = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if let first = value.unicodeScalars.first, word.contains(first), range.location > 0,
           let previous = UnicodeScalar(input.character(at: range.location - 1)), word.contains(previous) { return false }
        if let last = value.unicodeScalars.last, word.contains(last), NSMaxRange(range) < input.length,
           let next = UnicodeScalar(input.character(at: NSMaxRange(range))), word.contains(next) { return false }
        return true
    }

    private func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
