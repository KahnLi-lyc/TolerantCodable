import Foundation
import XCTest
@testable import TolerantCodable

final class LossyWrapperTests: XCTestCase {
    private struct Profile: Codable, Hashable, Sendable {
        @LYLossyDictionary var scores: [String: Int]
        @LYLossyDictionary var byID: [Int: String]
        @LYLossyOptional var age: Int?
        @LYLossyOptional var nickname: String?
    }

    private struct Aliased: Decodable {
        @LYDefaultString var name: String
        @LYDefaultInt var count: Int
        @LYDefaultInt64 var wide: Int64
        @LYDefaultDouble var ratio: Double
        @LYDefaultFloat var scale: Float
        @LYDefaultDecimal var amount: Decimal
        @LYDefaultFalse var off: Bool
        @LYDefaultTrue var on: Bool
        @LYDefaultEmptyArray<String> var tags: [String]
        @LYDefaultEmptyDictionary<String, Int> var counts: [String: Int]
    }

    private func reasons(_ entries: [LYDecodingDiagnostic]) -> Set<String> {
        Set(entries.map { "\($0.kind)|\($0.codingPath.joined(separator: "."))|\($0.reason)" })
    }

    func testLossyDictionaryDropsBadEntriesAndRecordsThem() throws {
        let recorder = DiagnosticRecorder()
        let json = #"{"scores":{"a":1,"b":"x","c":3},"byID":{"1":"one","x":"bad","2":2},"age":30,"nickname":null}"#
        let profile = try recorder.coder().decode(Profile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.scores, ["a": 1, "c": 3])
        XCTAssertEqual(profile.byID, [1: "one"])
        XCTAssertEqual(profile.age, 30)
        XCTAssertNil(profile.nickname)
        XCTAssertEqual(reasons(recorder.entries), [
            "discard|scores.b|invalid_dictionary_value",
            "discard|byID.x|invalid_dictionary_key",
            "discard|byID.2|invalid_dictionary_value"
        ])
    }

    func testLossyDictionaryFallsBackForMissingNullAndNonObjects() throws {
        let recorder = DiagnosticRecorder()
        let profile = try recorder.coder().decode(Profile.self, from: Data(#"{"scores":null,"byID":[1]}"#.utf8))
        XCTAssertEqual(profile.scores, [:])
        XCTAssertEqual(profile.byID, [:])
        XCTAssertEqual(reasons(recorder.entries), ["fallback|scores|null_value", "fallback|byID|expected_object"])

        let missing = DiagnosticRecorder()
        _ = try missing.coder().decode(Profile.self, from: Data("{}".utf8))
        XCTAssertEqual(reasons(missing.entries), ["fallback|scores|missing_key", "fallback|byID|missing_key"])
    }

    func testLossyDictionaryKeepsRawKeysUnderSnakeCase() throws {
        var configuration = LYCodingConfiguration.snakeCase
        configuration.diagnosticLimit = 10
        let coder = LYJSONCoder(configuration: configuration)
        let clean = try coder.decode(Profile.self, from: Data(#"{"scores":{"user_id":1},"by_i_d":{}}"#.utf8))
        let dirty = try coder.decode(Profile.self, from: Data(#"{"scores":{"user_id":1,"bad_one":"x"}}"#.utf8))
        XCTAssertEqual(clean.scores, ["user_id": 1])
        XCTAssertEqual(dirty.scores, ["user_id": 1], "Fast and lossy paths must agree on raw keys")
    }

    func testLossyOptionalTurnsTypeMismatchIntoNil() throws {
        let recorder = DiagnosticRecorder()
        let profile = try recorder.coder().decode(Profile.self, from: Data(#"{"scores":{},"byID":{},"age":"thirty","nickname":7}"#.utf8))
        XCTAssertNil(profile.age)
        XCTAssertNil(profile.nickname)
        XCTAssertEqual(reasons(recorder.entries), ["fallback|age|incompatible_value", "fallback|nickname|incompatible_value"])
    }

    func testEncodingRoundTripsAndOmitsNilOptionals() throws {
        var profile = try Profile.decode(fromJSON: #"{"scores":{"a":1},"byID":{"7":"seven"},"age":3}"#)
        let object = try profile.jsonDictionary()
        XCTAssertNil(object["nickname"], "nil LYLossyOptional must omit the key")
        XCTAssertEqual((object["byID"] as? [String: Any])?["7"] as? String, "seven")
        XCTAssertEqual(try Profile.decode(fromJSON: profile.jsonData()), profile)
        profile.nickname = "n"
        XCTAssertEqual(try profile.jsonDictionary()["nickname"] as? String, "n")
        XCTAssertEqual(try LYJSONCoder().encodeString(LYLossyOptional<Int>()), "null")
        XCTAssertEqual(Set([profile]).count, 1)
    }

    func testDefaultAliasesBehaveLikeTheirProviders() throws {
        let value = try Aliased.decode(fromJSON: #"{"count":"5","on":"0"}"#)
        XCTAssertEqual(value.name, "")
        XCTAssertEqual(value.count, 5)
        XCTAssertEqual(value.wide, 0)
        XCTAssertEqual(value.ratio, 0)
        XCTAssertEqual(value.scale, 0)
        XCTAssertEqual(value.amount, 0)
        XCTAssertFalse(value.off)
        XCTAssertFalse(value.on)
        XCTAssertEqual(value.tags, [])
        XCTAssertEqual(value.counts, [:])
        XCTAssertTrue(try Aliased.decode(fromJSON: "{}").on)
    }
}

/// 新包装器的快速路径同样必须与兼容路径一致。
final class LossyFastPathTests: XCTestCase {
    private struct Wrapped: Decodable {
        @LYLossyDictionary var map: [Int: Int]
        @LYLossyOptional var maybe: Int?
    }

    private struct Reference: Decodable {
        let map: [Int: Int]
        let maybe: Int?
        private enum CodingKeys: String, CodingKey { case map, maybe }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if c.contains(.map) {
                map = try LYLossyDictionary<Int, Int>(from: c.superDecoder(forKey: .map)).wrappedValue
            } else {
                (try? c.superDecoder(forKey: .map))?.lyRecord(.fallback, target: [Int: Int].self, reason: "missing_key")
                map = [:]
            }
            maybe = c.contains(.maybe) ? try LYLossyOptional<Int>(from: c.superDecoder(forKey: .maybe)).wrappedValue : nil
        }
    }

    func testResultsAndDiagnosticsMatchTheCompatibilityPath() throws {
        let inputs = [
            #"{"map":{"1":1,"2":2},"maybe":3}"#,
            #"{"map":{"1":"x","b":2,"3":3},"maybe":"3"}"#,
            #"{"map":null,"maybe":null}"#,
            #"{"map":[1],"maybe":[1]}"#,
            #"{"map":{},"maybe":1.5}"#,
            "{}"
        ]
        let strip: (LYDecodingDiagnostic) -> String = { "\($0.kind)|\($0.codingPath)|\($0.reason)" }
        for json in inputs {
            let wrappedRecorder = DiagnosticRecorder()
            let referenceRecorder = DiagnosticRecorder()
            let wrapped = try wrappedRecorder.coder().decode(Wrapped.self, from: Data(json.utf8))
            let reference = try referenceRecorder.coder().decode(Reference.self, from: Data(json.utf8))
            XCTAssertEqual(wrapped.map, reference.map, json)
            XCTAssertEqual(wrapped.maybe, reference.maybe, json)
            XCTAssertEqual(Set(wrappedRecorder.entries.map(strip)), Set(referenceRecorder.entries.map(strip)), json)
        }
    }
}
