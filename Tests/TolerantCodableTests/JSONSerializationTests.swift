import Foundation
import TolerantCodable
import XCTest

final class JSONSerializationTests: XCTestCase {
    func testNestedRoundTripPreservesNullBooleanAndUnicode() throws {
        let source: [String: Any] = ["text": "你好👋", "values": [true, NSNull(), 42, ["url": "https://example.test/a"]]]
        let string = try LYJSONSerialization.string(from: source, options: [.sortedKeys, .withoutEscapingSlashes])
        let data = try LYJSONSerialization.data(from: source)
        let fromString = try XCTUnwrap(LYJSONSerialization.parse(string) as? NSDictionary)
        let fromData = try XCTUnwrap(LYJSONSerialization.parse(data) as? NSDictionary)
        XCTAssertEqual(fromString, fromData)
        XCTAssertEqual(fromString["text"] as? String, "你好👋")
        let values = try XCTUnwrap(fromString["values"] as? [Any])
        XCTAssertEqual((values[0] as? NSNumber)?.objCType.pointee, NSNumber(value: true).objCType.pointee)
        XCTAssertTrue(values[1] is NSNull)
        XCTAssertTrue(string.contains("https://example.test/a"))
        XCTAssertTrue(try LYJSONSerialization.parse("[]") is [Any])
    }

    func testFragmentsRequireExplicitOptions() throws {
        for text in ["null", "true", "42", "\"你好\""] {
            XCTAssertThrowsError(try LYJSONSerialization.parse(text))
            _ = try LYJSONSerialization.parse(text, options: .fragmentsAllowed)
        }
        for value: Any in [NSNull(), true, 42, "你好"] {
            XCTAssertThrowsError(try LYJSONSerialization.data(from: value))
            let string = try LYJSONSerialization.string(from: value, options: .fragmentsAllowed)
            _ = try LYJSONSerialization.parse(string, options: .fragmentsAllowed)
        }
    }

    func testInvalidObjectsAndMalformedTextThrowInsteadOfFallback() {
        for input in ["", "{", "[1,]garbage"] {
            XCTAssertThrowsError(try LYJSONSerialization.parse(input))
        }
        XCTAssertThrowsError(try LYJSONSerialization.parse(Data([0xFF, 0xFE, 0x00])))
        for value: Any in [Date(), ["bad": Date()], [Double.nan], [Double.infinity]] {
            XCTAssertThrowsError(try LYJSONSerialization.data(from: value))
            XCTAssertThrowsError(try LYJSONSerialization.string(from: value, options: .fragmentsAllowed))
        }
    }

    func testFormattingOptionsAreExplicit() throws {
        let object = ["z": 1, "a": 2]
        XCTAssertEqual(try LYJSONSerialization.string(from: object, options: .sortedKeys), "{\"a\":2,\"z\":1}")
        XCTAssertTrue(try LYJSONSerialization.string(from: object, options: .prettyPrinted).contains("\n"))
    }
}
