import Foundation
import XCTest
@testable import TolerantCodable

/// LYScalar 必须与 @LYDefault 的兼容规则一致：同一 JSON 标量，要么两者结果相同，要么 LYDefault 回退且 LYScalar 抛错。
final class ScalarTests: XCTestCase {
    private struct Box<P: LYDefaultValueProvider>: Decodable { @LYDefault<P> var value: P.Value }

    private static let inputs = [
        #""abc""#, #"" 12 ""#, #""12""#, #""-7.9""#, #""1e3""#, #""0x10""#, #""nan""#, #""inf""#, #""""#, #""  ""#,
        #""TRUE""#, #""false""#, #""1""#, #""0""#, #""yes""#, #""9223372036854775807""#, #""9223372036854775808""#,
        #"" 3.5 ""#, "0", "1", "2", "-1", "3.7", "-3.7", "2.0", "1e3", "9223372036854775807", "-9223372036854775808",
        "1e30", "true", "false", "null", "[]", "{}", "[1]"
    ]

    /// 用 @LYDefault 解码，回退（记录 fallback）时返回 nil。
    private func viaDefault<P: LYDefaultValueProvider>(_ json: String, _: P.Type) throws -> P.Value? {
        let recorder = DiagnosticRecorder()
        let box = try recorder.coder().decode(Box<P>.self, from: Data(#"{"value":\#(json)}"#.utf8))
        return recorder.entries.contains { $0.kind == .fallback } ? nil : box.value
    }

    private func check<P: LYDefaultValueProvider>(
        _ provider: P.Type,
        _ convert: (Any?) throws -> P.Value
    ) throws where P.Value: Equatable {
        for json in Self.inputs {
            let expected = try viaDefault(json, provider)
            let foundation = try LYJSONSerialization.parse(Data(json.utf8), options: .fragmentsAllowed)
            let jsonValue = try JSONDecoder().decode(LYJSONValue.self, from: Data(json.utf8))
            for input in [foundation, jsonValue] as [Any] {
                let actual = try? convert(input)
                XCTAssertEqual(actual, expected, "\(P.Value.self) ← \(json) via \(type(of: input))")
            }
        }
    }

    func testMatchesLYDefaultForEveryTarget() throws {
        try check(LYDefaults.String.self, LYScalar.string(from:))
        try check(LYDefaults.Int.self, LYScalar.int(from:))
        try check(LYDefaults.Int64.self, LYScalar.int64(from:))
        try check(LYDefaults.Double.self, LYScalar.double(from:))
        try check(LYDefaults.Float.self, LYScalar.float(from:))
        try check(LYDefaults.Decimal.self, LYScalar.decimal(from:))
        try check(LYDefaults.False.self, LYScalar.bool(from:))
    }

    func testNativeSwiftValuesAndErrors() throws {
        XCTAssertEqual(try LYScalar.int(from: "42"), 42)
        XCTAssertEqual(try LYScalar.int(from: 3.9), 3)
        XCTAssertEqual(try LYScalar.bool(from: 1), true)
        XCTAssertEqual(try LYScalar.bool(from: true), true)
        XCTAssertEqual(try LYScalar.string(from: false), "false")
        XCTAssertEqual(try LYScalar.string(from: Decimal(string: "1.25")), "1.25")
        XCTAssertEqual(try LYScalar.double(from: LYJSONValue.integer(2)), 2)
        let optional: Int? = 5
        XCTAssertEqual(try LYScalar.int64(from: optional as Any), 5)
        XCTAssertThrowsError(try LYScalar.int(from: nil)) { error in
            XCTAssertEqual(error as? LYConversionError, .incompatibleScalar(target: "Swift.Int", source: .null))
        }
        XCTAssertThrowsError(try LYScalar.bool(from: "yes")) { error in
            XCTAssertEqual(error as? LYConversionError, .incompatibleScalar(target: "Swift.Bool", source: .string))
        }
        XCTAssertThrowsError(try LYScalar.string(from: Date())) { error in
            XCTAssertEqual(error as? LYConversionError, .unsupportedValue(typeName: "Foundation.Date"))
        }
    }
}
