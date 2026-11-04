import Foundation
import XCTest
@testable import TolerantCodable

private struct Message: Codable, Equatable, Sendable {
    let id: Int
    @LYDefaultString var text: String

    init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}

private struct MessageEntity: Decodable, Equatable {
    let id: Int
    let text: String
}

final class ConversionToolkitTests: XCTestCase {
    func testDataFromAnyNormalizesSocketPayloads() throws {
        let json = #"{"id":1,"text":"你好"}"#
        let inputs: [Any?] = [
            json,
            json as NSString,
            Data(json.utf8),
            Data(json.utf8) as NSData,
            ["id": 1, "text": "你好"] as [String: Any],
            ["id": 1, "text": "你好"] as NSDictionary,
            ["id": 1, "text": "你好"] as LYJSONValue
        ]
        for input in inputs {
            XCTAssertEqual(try Message.decode(fromAny: input), Message(id: 1, text: "你好"), "\(String(describing: input))")
        }
        XCTAssertEqual(try [Int].decode(fromAny: [1, 2] as [Any]), [1, 2])
        XCTAssertEqual(try [Int].decode(fromAny: NSArray(array: [3])), [3])
        XCTAssertEqual(try Int.decode(fromAny: ["data": ["n": 7]] as [String: Any], atPath: "data.n"), 7)
    }

    func testDataFromAnyRejectsUnsupportedInputs() {
        let cases: [(Any?, String)] = [(nil, "nil"), (NSNull(), "NSNull"), (Date(), "Foundation.Date"), (42, "Swift.Int")]
        for (input, typeName) in cases {
            XCTAssertThrowsError(try LYJSONSerialization.data(fromAny: input)) { error in
                XCTAssertEqual(error as? LYConversionError, .unsupportedValue(typeName: typeName))
            }
        }
        XCTAssertThrowsError(try LYJSONSerialization.data(fromAny: ["bad": Date()] as [String: Any]))
        XCTAssertThrowsError(try Message.decode(fromAny: "{"), "Text is validated by the decoder")
    }

    func testTypedParsingChecksTheRootKind() throws {
        XCTAssertEqual(try LYJSONSerialization.parseObject(#"{"a":1}"#)["a"] as? Int, 1)
        XCTAssertEqual(try LYJSONSerialization.parseArray(Data("[1,2]".utf8)).count, 2)
        XCTAssertThrowsError(try LYJSONSerialization.parseObject("[1]")) { error in
            XCTAssertEqual(error as? LYConversionError, .unexpectedRoot(expected: .object, actual: .array))
        }
        XCTAssertThrowsError(try LYJSONSerialization.parseArray(#"{"a":1}"#)) { error in
            XCTAssertEqual(error as? LYConversionError, .unexpectedRoot(expected: .array, actual: .object))
        }
        XCTAssertThrowsError(try LYJSONSerialization.parseObject("{"))
    }

    func testStandardLibraryExtensionsRoundTrip() throws {
        let source: [String: Any] = ["text": "你好👋", "list": [true, NSNull(), 1.5], "url": "https://example.test/a"]
        let string = try source.lyJSONString(options: [.sortedKeys, .withoutEscapingSlashes])
        XCTAssertEqual(string, #"{"list":[true,null,1.5],"text":"你好👋","url":"https://example.test/a"}"#)
        let parsed = try string.lyJSONDictionary()
        XCTAssertEqual(parsed["text"] as? String, "你好👋")
        XCTAssertTrue((parsed["list"] as? [Any])?[1] is NSNull)
        XCTAssertEqual(try source.lyJSONData().lyJSONDictionary().count, 3)

        let array: [Any] = [1, "two", ["three": 3]]
        XCTAssertEqual(try array.lyJSONString(), #"[1,"two",{"three":3}]"#)
        XCTAssertEqual(try array.lyJSONData().lyJSONArray().count, 3)
        XCTAssertEqual(try "[1]".lyJSONArray().first as? Int, 1)
        XCTAssertTrue(try "42".lyJSONObject(options: .fragmentsAllowed) is NSNumber)
        XCTAssertThrowsError(try "42".lyJSONObject())
        XCTAssertThrowsError(try ["date": Date()].lyJSONString())
        XCTAssertThrowsError(try "[1]".lyJSONDictionary())

        let pretty = try Data(#"{"b":1,"a":{"c":"https://x.test/"}}"#.utf8).lyPrettyJSONString()
        XCTAssertTrue(pretty.contains("\n"))
        XCTAssertTrue(pretty.contains("https://x.test/"))
        XCTAssertLessThan(try XCTUnwrap(pretty.range(of: "\"a\"")).lowerBound, try XCTUnwrap(pretty.range(of: "\"b\"")).lowerBound)
        XCTAssertEqual(try Data("true".utf8).lyPrettyJSONString(), "true")
        XCTAssertThrowsError(try Data("{".utf8).lyPrettyJSONString())
    }

    func testEncodableTypedOutputsAndModelConversion() throws {
        let message = Message(id: 1, text: "hi")
        let dictionary = try message.jsonDictionary()
        XCTAssertEqual(dictionary["id"] as? Int, 1)
        XCTAssertEqual(try [message].jsonArray().count, 1)
        XCTAssertThrowsError(try [message].jsonDictionary()) { error in
            XCTAssertEqual(error as? LYConversionError, .unexpectedRoot(expected: .object, actual: .array))
        }
        XCTAssertThrowsError(try message.jsonArray())
        XCTAssertEqual(try message.jsonValue(), ["id": 1, "text": "hi"])
        XCTAssertEqual(try message.converted(to: MessageEntity.self), MessageEntity(id: 1, text: "hi"))

        let recorder = DiagnosticRecorder()
        let partial: [String: LYJSONValue] = ["id": 2]
        XCTAssertEqual(try partial.converted(to: Message.self, coder: recorder.coder()), Message(id: 2, text: ""))
        XCTAssertEqual(recorder.entries.map(\.reason), ["missing_key"])
        XCTAssertThrowsError(try partial.converted(to: MessageEntity.self))
    }
}
