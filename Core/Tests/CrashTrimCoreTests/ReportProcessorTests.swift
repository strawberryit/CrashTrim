import XCTest
@testable import CrashTrimCore

final class ReportProcessorTests: XCTestCase {
    private let serial = "SYNTHETIC-SERIAL-991"
    private let part = "820-SYNTHETIC-A"
    private let buildUUID = "ABCDEF12-3456-7890-ABCD-1234567890AB"

    private var textReport: String {
        """
        Process:               ExamplePrivateApp [12345]
        Path:                  /Users/syntheticuser/Private Project/ExamplePrivateApp.app/Contents/MacOS/ExamplePrivateApp
        Identifier:            org.synthetic.privateapp
        Version:               1.2.3.4 (51)
        Code Type:             ARM-64 (Native)
        Parent Process:        launchd [1]
        User ID:               501
        Date/Time:             2026-09-01 12:34:56.123 +0900
        OS Version:            macOS 15.8.1 (24G)
        Report Version:        12
        Incident Identifier:   11111111-2222-3333-4444-555555555555
        Hardware Model:        MacBookPro18,3
        Exception Type:        EXC_BAD_ACCESS (SIGSEGV)
        Exception Codes:       KERN_INVALID_ADDRESS at 0x0000000000000040
        Termination Reason:    Namespace SIGNAL, Code 11 Segmentation fault: 11
        Application Specific Information:
        Owner: synthetic@example.test; host lab-machine.local; IP 192.168.1.70; MAC aa:bb:cc:dd:ee:ff
        Serial Number: \(serial)
        Part Number: \(part)
        File: "/Users/syntheticuser/Private Project/person name.txt"
        Crashed Thread:        0
        Thread 0 Crashed:
        0   ExamplePrivateApp 0x0000000100123456 renderView + 16
        Thread 1:
        0   libsystem_kernel.dylib 0x0000000187654321 mach_msg_trap + 8
        Thread 0 crashed with ARM Thread State (64-bit):
            x0: 0x0000000000000040   pc: 0x0000000100123456
        Binary Images:
        0x100000000 - 0x100ffffff ExamplePrivateApp (51) <\(buildUUID)> /Applications/ExamplePrivateApp.app/Contents/MacOS/ExamplePrivateApp
        VM Region Summary:
        TOTAL 1.2G
        Unknown Diagnostic Section:
        useful unknown detail 7
        Model: MacBookPro18,3, 16 GB
        Graphics: Apple M1
        USB Device: synthetic device
        Later Unknown Section:
        must remain
        """
    }

    private var ips: String {
        """
        {"app_name":"ExamplePrivateApp","app_version":"1.2.3.4","timestamp":"2026-09-01 12:34:56 +0900","incident_id":"11111111-2222-3333-4444-555555555555","share_with_app_devs":1}
        {
          "procName":"ExamplePrivateApp", "procPath":"/Users/syntheticuser/Secret Folder/ExamplePrivateApp.app/Contents/MacOS/ExamplePrivateApp",
          "pid":12345, "parentPid":1, "userID":501, "modelCode":"MacBookPro18,3", "uptime":10000,
          "bundleInfo":{"CFBundleIdentifier":"org.synthetic.privateapp","CFBundleShortVersionString":"1.2.3.4"},
          "osVersion":{"train":"macOS 15.8.1","build":"24G"},
          "exception":{"type":"EXC_BAD_ACCESS","codes":"0x0, 0x40"},
          "termination":{"namespace":"SIGNAL","code":11,"byPid":12345},
          "faultingThread":0,
          "threads":[{"id":0,"triggered":true,"frames":[{"imageIndex":0,"imageOffset":16,"symbol":"renderView","symbolLocation":4}],"threadState":{"pc":{"value":18446744073709551615}}},{"id":1,"frames":[{"imageIndex":1,"imageOffset":8,"symbol":"mach_msg_trap"}]}],
          "usedImages":[{"name":"ExamplePrivateApp","path":"/Applications/ExamplePrivateApp.app/Contents/MacOS/ExamplePrivateApp","uuid":"\(buildUUID)","base":4294967296,"size":4096},{"name":"libsystem_kernel.dylib","path":"/usr/lib/system/libsystem_kernel.dylib","uuid":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","base":6442450944,"size":4096}],
          "diagnostic":{"ownerEmail":"synthetic@example.test","serialNumber":"\(serial)","partNumber":"\(part)","filePath":"/Users/syntheticuser/Secret Folder/private file.txt","message":"\(serial) at /Users/syntheticuser/Secret Folder/private file.txt","enabled":true,"empty":null},
          "unknownFutureField":{"counter":7,"message":"must remain"}
        }
        """
    }

    func testTextMasksIdentifiersAndPreservesAllDiagnosticSections() throws {
        let result = try ReportProcessor.process(textReport)
        XCTAssertTrue(result.recognized)
        for forbidden in [serial, part, buildUUID, "syntheticuser", "Private Project", "person name.txt", "ExamplePrivateApp", "org.synthetic.privateapp", "MacBookPro18,3", "synthetic@example.test", "lab-machine.local", "192.168.1.70", "aa:bb:cc:dd:ee:ff", "2026-09-01"] {
            XCTAssertFalse(result.output.contains(forbidden), "Leaked: \(forbidden)")
        }
        for preserved in ["1.2.3.4 (51)", "macOS 15.8.1", "ARM-64", "Exception Type:", "Termination Reason:", "Thread 0 Crashed:", "Thread 1:", "ARM Thread State", "0x0000000100123456", "renderView + 16", "Binary Images:", "VM Region Summary:", "useful unknown detail 7", "Later Unknown Section:", "must remain"] {
            XCTAssertTrue(result.output.contains(preserved), "Lost: \(preserved)")
        }
        XCTAssertFalse(result.output.contains("USB Device:"))
        XCTAssertFalse(result.output.contains("Report Version:"))
        XCTAssertGreaterThan(result.maskedOccurrences, 15)
        XCTAssertGreaterThan(result.removedItems, 0)
    }

    func testIPSRemainsTwoJSONObjectsWithExactIntegersAndFrameRelationships() throws {
        let result = try ReportProcessor.process(ips)
        let objects = try XCTUnwrap(ReportParser.jsonObjects(result.output))
        XCTAssertEqual(objects.count, 2)
        for forbidden in [serial, part, buildUUID, "syntheticuser", "Secret Folder", "private file.txt", "ExamplePrivateApp", "org.synthetic.privateapp", "MacBookPro18,3", "synthetic@example.test", "2026-09-01"] {
            XCTAssertFalse(result.output.contains(forbidden), "Leaked: \(forbidden)")
        }
        guard case .object(let body) = objects[1], case .array(let threads)? = body["threads"],
              case .array(let images)? = body["usedImages"], case .object(let diagnostic)? = body["diagnostic"] else { return XCTFail("Missing structural data") }
        XCTAssertEqual(threads.count, 2)
        XCTAssertEqual(images.count, 2)
        if case .number? = body["pid"] {} else { XCTFail("PID type changed") }
        XCTAssertNotEqual(body["pid"]?.encoded(), "12345")
        guard case .object(let termination)? = body["termination"] else { return XCTFail() }
        XCTAssertEqual(body["pid"]?.encoded(), termination["byPid"]?.encoded())
        XCTAssertEqual(body["faultingThread"]?.encoded(), "0")
        XCTAssertEqual(body["uptime"]?.encoded(), "10000")
        XCTAssertEqual(diagnostic["enabled"]?.encoded(), "true")
        XCTAssertEqual(diagnostic["empty"]?.encoded(), "null")
        XCTAssertNotNil(body["unknownFutureField"])
        XCTAssertTrue(result.output.contains("18446744073709551615"))
        XCTAssertTrue(result.output.contains("\"imageIndex\": 0"))
        XCTAssertTrue(result.output.contains("\"imageIndex\": 1"))
        XCTAssertTrue(result.output.contains("\"imageOffset\": 16"))
        XCTAssertTrue(result.output.contains("1.2.3.4"))
        XCTAssertTrue(result.output.contains("libsystem_kernel.dylib"))
        XCTAssertTrue(result.output.contains("/usr/lib/system/libsystem_kernel.dylib"))
    }

    func testSingleJSONAndTranslatedReportUseCompleteJSON() throws {
        let body = ips.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        let single = try ReportProcessor.process(body)
        XCTAssertEqual(ReportParser.jsonObjects(single.output)?.count, 1)
        let combined = "Translated Report (Full Report Below)\n" + textReport + "\nFull Report:\n-----------\n" + ips
        let result = try ReportProcessor.process(combined)
        XCTAssertEqual(ReportParser.jsonObjects(result.output)?.count, 2)
        XCTAssertFalse(result.output.contains("Translated Report"))
        XCTAssertGreaterThan(result.removedCharacters, single.removedCharacters)
    }

    func testUnknownAndDamagedJSONMaskWithoutTrimming() throws {
        let unknown = "Header must remain\nSerial Number: \(serial)\nUnfamiliar diagnostic\n/Users/testperson/file.txt\n"
        let result = try ReportProcessor.process(unknown)
        XCTAssertFalse(result.recognized)
        XCTAssertEqual(result.removedItems, 0)
        XCTAssertTrue(result.output.contains("Unfamiliar diagnostic"))
        XCTAssertFalse(result.output.contains(serial))
        XCTAssertFalse(result.output.contains("testperson"))
        let damaged = #"{"username":"syntheticuser","serialNumber":"SYNTHETIC-SERIAL-991","pid":12345,"unknown":"keep", BROKEN"#
        let masked = try ReportProcessor.process(damaged)
        XCTAssertFalse(masked.recognized)
        XCTAssertFalse(masked.output.contains("syntheticuser"))
        XCTAssertFalse(masked.output.contains(serial))
        XCTAssertFalse(masked.output.contains("12345"))
        XCTAssertTrue(masked.output.contains("BROKEN"))
        let nonCrashJSON = try ReportProcessor.process(#"{"username":"syntheticuser","unknown":5}"#)
        XCTAssertFalse(nonCrashJSON.recognized)
        XCTAssertFalse(nonCrashJSON.output.contains("syntheticuser"))
    }

    func testAdditionalLiteralsLongestFirstCaseSensitiveWithoutRegexOrPlaceholderRecursion() throws {
        let result = try ReportProcessor.process("Ann Ann Lee ann a.b aXb [CUSTOM_1] 민수 민수", additionalStrings: "Ann\nAnn Lee\na.b\n민수")
        XCTAssertFalse(result.output.contains("Ann"))
        XCTAssertTrue(result.output.contains("ann"))
        XCTAssertFalse(result.output.contains("a.b"))
        XCTAssertTrue(result.output.contains("aXb"))
        XCTAssertFalse(result.output.contains("민수"))
        XCTAssertTrue(result.output.contains("[CUSTOM_1]"))
        XCTAssertEqual(result.maskedOccurrences, 5)
    }

    func testRepeatedValuesGetSameAliasAcrossFieldsAndDiagnostics() throws {
        let result = try ReportProcessor.process("Serial Number: \(serial)\nSeen \(serial) and \(serial)\n")
        XCTAssertEqual(result.output.components(separatedBy: "[SERIAL_1]").count - 1, 3)
        XCTAssertEqual(result.maskedOccurrences, 3)
    }

    func testIPv6AndUnknownSectionArePreservedExceptSensitiveValues() throws {
        let result = try ReportProcessor.process("Peer 2001:db8::1 and ::1; Host name: \"x\"\nEmail: a@b.test\nKeep unfamiliar section\n")
        XCTAssertFalse(result.output.contains("2001:db8::1"))
        XCTAssertFalse(result.output.contains("::1"))
        XCTAssertFalse(result.output.contains("a@b.test"))
        XCTAssertTrue(result.output.contains("Keep unfamiliar section"))
    }

    func testEmptyInput() throws {
        let result = try ReportProcessor.process("")
        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.maskedOccurrences, 0)
    }

    func testSchemaKeysAreNotChangedByAnAppNamedName() throws {
        let input = #"{"procName":"name","pid":900001,"exception":{"type":"EXC_BAD_ACCESS"},"threads":[{"id":0,"name":"worker","frames":[{"imageIndex":0}]}],"usedImages":[{"name":"name","path":"/Applications/name.app/Contents/MacOS/name"}]}"#
        let result = try ReportProcessor.process(input)
        let objects = try XCTUnwrap(ReportParser.jsonObjects(result.output))
        guard case .object(let body) = objects[0], case .array(let images)? = body["usedImages"],
              case .object(let image) = images.first else { return XCTFail("Schema changed") }
        XCTAssertNotNil(image["name"])
        XCTAssertNotEqual(body["pid"]?.encoded(), "900001")
    }

    func testUnquotedPrivatePathWithSpacesAndEscapedMalformedIdentifier() throws {
        let result = try ReportProcessor.process("Open /Users/syntheticuser/Secret Folder/private name.txt\nkeep next line")
        XCTAssertFalse(result.output.contains("Secret Folder"))
        XCTAssertFalse(result.output.contains("private name.txt"))
        XCTAssertTrue(result.output.contains("keep next line"))
        let damaged = #"{"username":"synthetic\u0075ser", BROKEN"#
        let masked = try ReportProcessor.process(damaged)
        XCTAssertFalse(masked.output.contains(#"synthetic\u0075ser"#))
        XCTAssertTrue(masked.output.contains("BROKEN"))
    }

    func testStringIDsPreserveTypeAndNumericAliasNeverMatchesAnotherOriginalID() throws {
        let input = #"{"pid":"12345","parentPid":900001,"userID":"501","exception":{"type":"EXC_BAD_ACCESS"},"threads":[],"roots_installed":1}"#
        let result = try ReportProcessor.process(input)
        let objects = try XCTUnwrap(ReportParser.jsonObjects(result.output))
        guard case .object(let body) = objects[0], case .string(let pid)? = body["pid"],
              case .number(let parent)? = body["parentPid"], case .string(let uid)? = body["userID"] else { return XCTFail("Types changed") }
        for alias in [pid, parent, uid] { XCTAssertFalse(["12345", "900001", "501"].contains(alias)) }
        XCTAssertEqual(body["roots_installed"]?.encoded(), "1")
    }

    func testFourPartVersionIsPreservedEvenWhenAnIPHasTheSameValue() throws {
        let text = try ReportProcessor.process("Version: 1.2.3.4\nPeer: 1.2.3.4\n")
        XCTAssertTrue(text.output.contains("Version: 1.2.3.4"))
        XCTAssertFalse(text.output.contains("Peer: 1.2.3.4"))
        let json = try ReportProcessor.process(#"{"app_version":"1.2.3.4","diagnostic":{"peer":"1.2.3.4"},"exception":{"type":"EXC_BAD_ACCESS"},"threads":[]}"#)
        XCTAssertTrue(json.output.contains("\"app_version\": \"1.2.3.4\""))
        XCTAssertFalse(json.output.contains("\"peer\": \"1.2.3.4\""))
    }

    func testPrivatePathsInArraysAreDiscoveredBeforeEncoding() throws {
        let input = #"{"exception":{"type":"EXC_BAD_ACCESS"},"threads":[],"diagnostics":["/Users\u002Ftestperson/Private Folder/file.txt","/opt/privatecompany/project/file.txt","~/Documents/private file.txt"]}"#
        let result = try ReportProcessor.process(input)
        XCTAssertFalse(result.output.contains("testperson"))
        XCTAssertFalse(result.output.contains("Private Folder"))
        XCTAssertFalse(result.output.contains("privatecompany"))
        XCTAssertFalse(result.output.contains("private file.txt"))
        XCTAssertNotNil(ReportParser.jsonObjects(result.output))
    }

    func testOnlyHardwareAppendixIsRemovedAndExistingPlaceholdersDoNotCollide() throws {
        let input = "Process: Example [123]\nException Type: EXC_BAD_ACCESS\nApplication Specific Information:\nModel: diagnostic model\nThread 0:\n0 Example 0x10000 failure + 1\nBinary Images:\nModel: Mac14,2\nGraphics: Apple M2\n"
        let result = try ReportProcessor.process(input)
        XCTAssertEqual(result.output.components(separatedBy: "Model:").count - 1, 1)
        XCTAssertTrue(result.output.contains("Thread 0:"))
        XCTAssertFalse(result.output.contains("Graphics:"))
        let custom = try ReportProcessor.process("[CUSTOM_1] secret [SERIAL_1]", additionalStrings: "[CUSTOM_1]\nsecret\n[SERIAL_1]")
        XCTAssertFalse(custom.output.contains("[CUSTOM_1]"))
        XCTAssertFalse(custom.output.contains("[SERIAL_1]"))
        XCTAssertFalse(custom.output.contains("secret"))
        XCTAssertEqual(custom.maskedOccurrences, 3)
    }

    func testLargeLog() throws {
        let lines = (0..<20_000).map { "\($0) libsystem 0x100000001 renderView + 4" }.joined(separator: "\n")
        let result = try ReportProcessor.process(textReport + "\nThread 2:\n" + lines)
        XCTAssertTrue(result.output.contains("19999 libsystem 0x100000001 renderView + 4"))
        XCTAssertTrue(result.output.contains("Thread 2:"))
    }
}
