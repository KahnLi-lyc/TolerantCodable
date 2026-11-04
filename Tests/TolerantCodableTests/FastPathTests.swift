import Foundation
import XCTest
@testable import TolerantCodable

/// 快速路径只是性能优化：任意输入下的解码结果和诊断都必须与"直接走兼容路径"完全一致。
final class FastPathTests: XCTestCase {
    private struct Wrapped: Decodable, Equatable {
        @LYDefault<LYDefaults.Int> var count: Int
        @LYDefault<LYDefaults.Double> var ratio: Double
        @LYDefault<LYDefaults.String> var name: String
        @LYDefault<LYDefaults.False> var flag: Bool
        @LYLossyArray var values: [Int]
    }

    /// 绕过 KeyedDecodingContainer 重载，强制每个字段经 superDecoder 走兼容路径，作为对照组。
    private struct Reference: Decodable, Equatable {
        let count: Int
        let ratio: Double
        let name: String
        let flag: Bool
        let values: [Int]

        private enum CodingKeys: String, CodingKey { case count, ratio, name, flag, values }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func missing(_ key: CodingKeys, _ target: Any.Type) {
                (try? c.superDecoder(forKey: key))?.lyRecord(.fallback, target: target, reason: "missing_key")
            }
            func field<P: LYDefaultValueProvider>(_ key: CodingKeys, _: P.Type) throws -> P.Value {
                guard c.contains(key) else {
                    missing(key, P.Value.self)
                    return P.defaultValue
                }
                return try LYDefault<P>(from: c.superDecoder(forKey: key)).wrappedValue
            }
            count = try field(.count, LYDefaults.Int.self)
            ratio = try field(.ratio, LYDefaults.Double.self)
            name = try field(.name, LYDefaults.String.self)
            flag = try field(.flag, LYDefaults.False.self)
            if c.contains(.values) {
                values = try LYLossyArray<Int>(from: c.superDecoder(forKey: .values)).wrappedValue
            } else {
                missing(.values, [Int].self)
                values = []
            }
        }
    }

    func testResultsAndDiagnosticsMatchTheCompatibilityPath() throws {
        let inputs = [
            #"{"count":3,"ratio":1.5,"name":"a","flag":true,"values":[1,2]}"#,
            #"{"count":"3","ratio":"1.5","name":7,"flag":1,"values":[1,"x",2]}"#,
            #"{"count":null,"ratio":"nan","name":null,"flag":"yes","values":null}"#,
            #"{"count":3.9,"ratio":"0x1p4","name":true,"flag":"FALSE","values":42}"#,
            #"{"count":9223372036854775808,"values":[]}"#,
            "{}"
        ]
        for json in inputs {
            let wrappedRecorder = DiagnosticRecorder()
            let referenceRecorder = DiagnosticRecorder()
            let wrapped = try wrappedRecorder.coder().decode(Wrapped.self, from: Data(json.utf8))
            let reference = try referenceRecorder.coder().decode(Reference.self, from: Data(json.utf8))
            XCTAssertEqual(wrapped.count, reference.count, json)
            XCTAssertEqual(wrapped.ratio, reference.ratio, json)
            XCTAssertEqual(wrapped.name, reference.name, json)
            XCTAssertEqual(wrapped.flag, reference.flag, json)
            XCTAssertEqual(wrapped.values, reference.values, json)
            let strip: (LYDecodingDiagnostic) -> String = { "\($0.kind)|\($0.codingPath)|\($0.reason)" }
            XCTAssertEqual(wrappedRecorder.entries.map(strip), referenceRecorder.entries.map(strip), json)
        }
    }

    func testCleanInputProducesNoDiagnostics() throws {
        let recorder = DiagnosticRecorder()
        _ = try recorder.coder().decode(Wrapped.self, from: Data(#"{"count":1,"ratio":2,"name":"n","flag":false,"values":[1]}"#.utf8))
        XCTAssertTrue(recorder.entries.isEmpty)
    }
}
