import Foundation
import os
import XCTest
@testable import TolerantCodable

final class CodingTests: XCTestCase {
    private struct Numbers: Codable, Equatable, Sendable {
        @LYDefault<LYDefaults.String> var text: String
        @LYDefault<LYDefaults.Int> var integer: Int
        @LYDefault<LYDefaults.Int64> var wide: Int64
        @LYDefault<LYDefaults.Double> var double: Double
        @LYDefault<LYDefaults.Float> var float: Float
        @LYDefault<LYDefaults.Decimal> var decimal: Decimal
        @LYDefault<LYDefaults.False> var boolean: Bool
        @LYDefault<LYDefaults.True> var enabled: Bool
    }

    private struct Lists: Codable, Equatable, Sendable {
        @LYLossyArray var values: [Int]
        @LYDefault<LYDefaults.EmptyArray<String>> var names: [String]
        @LYDefault<LYDefaults.EmptyDictionary<String, Int>> var counts: [String: Int]
    }

    private struct Timestamp: Codable, Equatable, Sendable {
        @LYFlexibleDate var date: Date
    }

    private struct Strict: Decodable {
        let required: String
        @LYDefault<LYDefaults.Int> var count: Int
        enum CodingKeys: String, CodingKey { case required
            case count = "count_value"
        }
    }

    func testMalformedTimezoneOffsetsFallBackToEpoch() throws {
        for text in ["2023-11-14T22:13:20+24:00", "2023-11-14T22:13:20+01:99", "2023-11-14T22:13:20-25:00"] {
            let data = try JSONEncoder().encode(["date": text])
            let value = try LYJSONCoder().decode(Timestamp.self, from: data)
            XCTAssertEqual(value.date, Date(timeIntervalSince1970: 0))
        }
    }

    func testFinalFailureSurvivesDiagnosticLimit() throws {
        struct Model: Decodable {
            enum CodingKeys: String, CodingKey { case values, required }
            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                _ = try container.decode([LYDefault<LYDefaults.Int>].self, forKey: .values)
                _ = try container.decode(String.self, forKey: .required)
            }
        }
        let recorder = DiagnosticRecorder()
        let invalidItems = Array(repeating: "{}", count: 51).joined(separator: ",")
        let data = Data("{\"values\":[\(invalidItems)],\"required\":42}".utf8)
        XCTAssertThrowsError(try recorder.coder().decode(Model.self, from: data))
        let entries = recorder.entries
        XCTAssertEqual(entries.count, 51)
        let failure = entries.first { $0.kind == .failure }
        XCTAssertEqual(failure?.codingPath, ["required"])
        XCTAssertEqual(failure?.reason, "type_mismatch")
        XCTAssertEqual(entries.last?.kind, .suppressed)
        XCTAssertEqual(entries.last?.reason, "2")
    }

    func testMissingAndNullFieldsUseDefaultsWithNativeDecoder() throws {
        let missing = try JSONDecoder().decode(Numbers.self, from: Data("{}".utf8))
        let null = try JSONDecoder().decode(
            Numbers.self,
            from: Data(
                #"{"text":null,"integer":null,"wide":null,"double":null,"float":null,"decimal":null,"boolean":null,"enabled":null}"#
                    .utf8
            )
        )
        XCTAssertEqual(missing, null)
        XCTAssertEqual(missing.text, "")
        XCTAssertEqual(missing.integer, 0)
        XCTAssertTrue(missing.enabled)
        XCTAssertFalse(missing.boolean)
    }

    func testLooseScalarConversionsPreserveIntegerAndDecimalPrecision() throws {
        let value = try LYJSONCoder().decode(
            Numbers.self,
            from: Data(
                #"{"text":9007199254740993,"integer":-12.9,"wide":"9223372036854775807","double":" 1.25 ","float":"2.5","decimal":"12345678901234567890.123456789","boolean":" TRUE ","enabled":0}"#
                    .utf8
            )
        )
        XCTAssertEqual(value.text, "9007199254740993")
        XCTAssertEqual(value.integer, -12)
        XCTAssertEqual(value.wide, .max)
        XCTAssertEqual(value.double, 1.25)
        XCTAssertEqual(value.float, 2.5)
        XCTAssertEqual(
            value.decimal,
            Decimal(string: "12345678901234567890.123456789", locale: Locale(identifier: "en_US_POSIX"))
        )
        XCTAssertTrue(value.boolean)
        XCTAssertFalse(value.enabled)
    }

    func testOverflowAndInvalidValuesFallBack() throws {
        let value = try LYJSONCoder().decode(
            Numbers.self,
            from: Data(
                #"{"integer":9223372036854775808,"wide":"9223372036854775808","double":"Infinity","float":"1e100","decimal":"garbage","boolean":"yes","enabled":[],"text":{}}"#
                    .utf8
            )
        )
        XCTAssertEqual(value.integer, 0)
        XCTAssertEqual(value.wide, 0)
        XCTAssertEqual(value.double, 0)
        XCTAssertEqual(value.float, 0)
        XCTAssertEqual(value.decimal, 0)
        XCTAssertFalse(value.boolean)
        XCTAssertTrue(value.enabled)
        XCTAssertEqual(value.text, "")
    }

    func testLossyArrayAdvancesPastNestedInvalidElements() throws {
        let coder = LYJSONCoder()
        let value = try coder.decode(
            Lists.self,
            from: Data(#"{"values":[1,"bad",{},[1,2],null,2,3],"names":null,"counts":false}"#.utf8)
        )
        XCTAssertEqual(value.values, [1, 2, 3])
        XCTAssertEqual(value.names, [])
        XCTAssertEqual(value.counts, [:])
        for body in ["{}", #"{"values":null}"#, #"{"values":42}"#] {
            XCTAssertEqual(try coder.decode(Lists.self, from: Data(body.utf8)).values, [])
        }
    }

    func testLossyArrayHonorsFoundationDateAndDataStrategies() throws {
        struct Dates: Decodable { @LYLossyArray var values: [Date] }
        struct Blobs: Decodable { @LYLossyArray var values: [Data] }
        let seconds = LYJSONCoder(configuration: .init(makeDecoder: {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return decoder
        }))
        XCTAssertEqual(
            try seconds.decode(Dates.self, from: Data(#"{"values":[1700000000,"bad",1700000001]}"#.utf8)).values
                .map(\.timeIntervalSince1970),
            [1_700_000_000, 1_700_000_001]
        )
        let iso = LYJSONCoder(configuration: .init(makeDecoder: {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return decoder
        }))
        XCTAssertEqual(
            try iso.decode(Dates.self, from: Data(#"{"values":["2023-11-14T22:13:20Z",{},"bad"]}"#.utf8)).values,
            [Date(timeIntervalSince1970: 1_700_000_000)]
        )
        let blobs = try LYJSONCoder().decode(
            Blobs.self,
            from: Data(#"{"values":["aGk=",{},"aA=="]}"#.utf8)
        )
        XCTAssertEqual(blobs.values, [Data("hi".utf8), Data("h".utf8)])
    }

    func testFlexibleDatesAndCanonicalEncoding() throws {
        let coder = LYJSONCoder()
        let seconds = 1_700_000_000.0
        for raw in [
            "1700000000",
            "1700000000000",
            #""1700000000""#,
            #""2023-11-14T22:13:20Z""#,
            #""2023-11-14T22:13:20.000+0000""#,
            #""2023-11-14 22:13:20""#
        ] {
            let value = try coder.decode(Timestamp.self, from: Data("{\"date\":\(raw)}".utf8))
            XCTAssertEqual(value.date.timeIntervalSince1970, seconds)
            XCTAssertTrue(try String(decoding: coder.encode(value), as: UTF8.self).contains("2023-11-14T22:13:20Z"))
        }
        for raw in [#""2023-02-30""#, #""Infinity""#, "null", "{}"] {
            XCTAssertEqual(
                try coder.decode(Timestamp.self, from: Data("{\"date\":\(raw)}".utf8)).date,
                Date(timeIntervalSince1970: 0)
            )
        }
        XCTAssertEqual(try coder.decode(Timestamp.self, from: Data("{}".utf8)).date, Date(timeIntervalSince1970: 0))
    }

    func testFlexibleDatesWithoutTimezoneOrWithSpaceSeparatorDecodeAsUTC() throws {
        let coder = LYJSONCoder()
        let cases: [(String, TimeInterval)] = [
            ("2023-11-14T22:13:20", 1_700_000_000),
            ("2023-11-14 22:13:20Z", 1_700_000_000),
            ("2023-11-14 22:13:20.125", 1_700_000_000.125),
            ("2023-11-14T22:13:20.123456789Z", 1_700_000_000.123456789),
            ("2023-11-14T22:13:20+08:00", 1_699_971_200),
            ("2023-11-14T22:13:20-05:30", 1_700_019_800)
        ]
        for (text, expected) in cases {
            let value = try coder.decode(Timestamp.self, from: JSONEncoder().encode(["date": text]))
            XCTAssertEqual(value.date.timeIntervalSince1970, expected, accuracy: 0.000_001, text)
        }
        for text in ["2023-11-14T24:00:00Z", "2023-11-14T22:13:60Z", "2023-11-14T22:13:20+0860"] {
            let value = try coder.decode(Timestamp.self, from: JSONEncoder().encode(["date": text]))
            XCTAssertEqual(value.date, Date(timeIntervalSince1970: 0), text)
        }
    }

    func testFlexibleDateRecordsConversionOnlyForNonCanonicalInput() throws {
        let records = OSAllocatedUnfairLock(initialState: [LYDecodingDiagnostic]())
        let coder = LYJSONCoder(configuration: .init(onDiagnostic: { record in
            records.withLock { $0.append(record) }
        }))
        for raw in [#""2023-11-14T22:13:20Z""#, #""2023-11-14T22:13:20.125+08:00""#] {
            _ = try coder.decode(Timestamp.self, from: Data("{\"date\":\(raw)}".utf8))
        }
        XCTAssertTrue(records.withLock { $0 }.isEmpty, "Canonical ISO8601 dates must not consume the diagnostic budget")
        for raw in ["1700000000", #""2023-11-14""#, #""2023-11-14 22:13:20""#, #""2023-11-14T22:13:20""#] {
            _ = try coder.decode(Timestamp.self, from: Data("{\"date\":\(raw)}".utf8))
        }
        let snapshot = records.withLock { $0 }
        XCTAssertEqual(snapshot.count, 4)
        XCTAssertTrue(snapshot.allSatisfy { $0.kind == .conversion && $0.reason == "compatible_date" })
    }

    func testFloatingConversionsUseTheStrictDecimalGrammar() throws {
        let coder = LYJSONCoder()
        let rejected = try coder.decode(Numbers.self, from: Data(#"{"double":"0x1p4","float":"nan"}"#.utf8))
        XCTAssertEqual(rejected.double, 0)
        XCTAssertEqual(rejected.float, 0)
        let accepted = try coder.decode(Numbers.self, from: Data(#"{"double":"-1.5e3","float":".5"}"#.utf8))
        XCTAssertEqual(accepted.double, -1500)
        XCTAssertEqual(accepted.float, 0.5)
    }

    func testLossyArrayFallbackReasonDistinguishesNullFromWrongType() throws {
        let records = OSAllocatedUnfairLock(initialState: [LYDecodingDiagnostic]())
        let coder = LYJSONCoder(configuration: .init(onDiagnostic: { record in
            records.withLock { $0.append(record) }
        }))
        _ = try coder.decode(Lists.self, from: Data(#"{"values":null,"names":[],"counts":{}}"#.utf8))
        _ = try coder.decode(Lists.self, from: Data(#"{"values":42,"names":[],"counts":{}}"#.utf8))
        let reasons = records.withLock { $0 }.filter { $0.codingPath == ["values"] }.map(\.reason)
        XCTAssertEqual(reasons, ["null_value", "expected_array"])
    }

    func testPlainRequiredFieldsAndRootRemainStrictAndAliasesWork() throws {
        let coder = LYJSONCoder()
        for body in ["{}", "[]", "null", "broken", #"{"required":42}"#] {
            XCTAssertThrowsError(try coder.decode(Strict.self, from: Data(body.utf8)))
        }
        let value = try coder.decode(Strict.self, from: Data(#"{"required":"yes","count_value":"7"}"#.utf8))
        XCTAssertEqual(value.count, 7)
    }

    func testDiagnosticsContainContextPathsAndNoRawSecrets() throws {
        let recorder = DiagnosticRecorder()
        let coder = recorder.coder()
        _ = try coder.decode(
            Strict.self,
            from: Data(#"{"required":"ok","count_value":"SECRET_TOKEN"}"#.utf8),
            context: .init(endpoint: "/fixture", requestID: "request-a")
        )
        let entries = recorder.entries
        XCTAssertTrue(entries.contains { $0.codingPath == ["count_value"] && $0.kind == .fallback })
        XCTAssertTrue(entries.allSatisfy { $0.context.requestID == "request-a" && $0.context.endpoint == "/fixture" })
        XCTAssertFalse("\(entries)".contains("SECRET_TOKEN"))
        XCTAssertThrowsError(try coder.decode(
            Strict.self,
            from: Data(#"{"required":"SECRET_TOKEN","count_value":{} } trailing SECRET_TOKEN"#.utf8)
        ))
        XCTAssertFalse("\(recorder.entries)".contains("SECRET_TOKEN"))
    }

    func testDiagnosticsAreBoundedAndConcurrentCallsRemainIsolated() async throws {
        let recorder = DiagnosticRecorder()
        let coder = recorder.coder()
        let invalids = Array(repeating: #""SECRET""#, count: 75).joined(separator: ",")
        let data = Data("{\"values\":[\(invalids)],\"names\":[],\"counts\":{}}".utf8)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0 ..< 4 {
                group.addTask {
                    _ = try coder.decode(Lists.self, from: data, context: .init(requestID: "decode-\(index)"))
                }
            }
            try await group.waitForAll()
        }
        for index in 0 ..< 4 {
            let entries = recorder.entries.filter { $0.context.requestID == "decode-\(index)" }
            XCTAssertEqual(entries.count, 51)
            XCTAssertTrue(entries.contains { $0.kind == .suppressed && $0.reason == "25" })
        }
        XCTAssertFalse("\(recorder.entries)".contains("SECRET"))
    }

    func testStructuredDiagnosticsIncludeMissingKeysArrayIndicesAndFailures() throws {
        let records = OSAllocatedUnfairLock(initialState: [LYDecodingDiagnostic]())
        let coder = LYJSONCoder(configuration: .init(onDiagnostic: { record in
            records.withLock { $0.append(record) }
        }))
        _ = try coder.decode(
            Lists.self,
            from: Data(#"{"values":[1,"bad",2]}"#.utf8),
            context: .init(requestID: "structured")
        )
        let snapshot = records.withLock { $0 }
        let discarded = try XCTUnwrap(snapshot.first { $0.kind == .discard })
        XCTAssertEqual(discarded.arrayIndex, 1)
        XCTAssertEqual(discarded.codingPath.first, "values")
        XCTAssertEqual(discarded.context.requestID, "structured")
        XCTAssertTrue(snapshot.contains { $0.codingPath == ["names"] && $0.reason == "missing_key" })
        XCTAssertThrowsError(try coder.decode(Strict.self, from: Data("{}".utf8)))
        XCTAssertTrue(records.withLock { $0 }.contains { $0.kind == .failure && $0.codingPath == ["required"] })
    }

    func testDateOnlyAndFractionalDatesRoundTripWithoutLosingMilliseconds() throws {
        let coder = LYJSONCoder()
        let dateOnly = try coder.decode(Timestamp.self, from: Data(#"{"date":"2024-02-29"}"#.utf8))
        XCTAssertEqual(dateOnly.date.timeIntervalSince1970, 1_709_164_800)
        let fractional = try coder.decode(Timestamp.self, from: Data(#"{"date":"2023-11-14T22:13:20.125Z"}"#.utf8))
        let roundTrip = try coder.decode(Timestamp.self, from: coder.encode(fractional))
        XCTAssertEqual(roundTrip.date.timeIntervalSince1970, fractional.date.timeIntervalSince1970, accuracy: 0.001)
    }

    func testConditionalConformancesAndCustomProviderRoundTrip() throws {
        enum Custom: LYDefaultValueProvider { static let defaultValue = "custom" }
        struct Value: Codable, Hashable, Sendable { @LYDefault<Custom> var name: String }
        let coder = LYJSONCoder()
        let value = try coder.decode(Value.self, from: Data("{}".utf8))
        XCTAssertEqual(value.name, "custom")
        XCTAssertEqual(Set([value]).count, 1)
        XCTAssertEqual(try coder.decode(Value.self, from: coder.encode(value)), value)
    }

    func testConfigurationCreatesIndependentCodersAndAppliesStrategies() throws {
        let configuration = LYCodingConfiguration(makeDecoder: {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return decoder
        }, makeEncoder: {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            return encoder
        })
        struct Value: Codable { let displayName: String }
        XCTAssertFalse(configuration.makeDecoder() === configuration.makeDecoder())
        XCTAssertFalse(configuration.makeEncoder() === configuration.makeEncoder())
        let coder = LYJSONCoder(configuration: configuration)
        let value = try coder.decode(Value.self, from: Data(#"{"display_name":"name"}"#.utf8))
        XCTAssertEqual(value.displayName, "name")
        XCTAssertTrue(try String(decoding: coder.encode(value), as: UTF8.self).contains("display_name"))
    }
}

/// 线程安全地收集 LYJSONCoder 的诊断回调。
final class DiagnosticRecorder: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [LYDecodingDiagnostic]())

    var entries: [LYDecodingDiagnostic] {
        storage.withLock { $0 }
    }

    func coder() -> LYJSONCoder {
        LYJSONCoder(configuration: .init(onDiagnostic: { [storage] record in
            storage.withLock { $0.append(record) }
        }))
    }
}
