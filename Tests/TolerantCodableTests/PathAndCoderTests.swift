import Foundation
import XCTest
@testable import TolerantCodable

final class PathAndCoderTests: XCTestCase {
    private struct Item: Codable, Equatable {
        let id: String
        @LYDefaultInt var age: Int

        init(id: String, age: Int) {
            self.id = id
            self.age = age
        }
    }

    private let envelope = #"{"data":{"items":[{"id":"a","age":1},{"id":"b","age":"x"}],"0":{"id":"key"}},"rows":[[1,2],[3]]}"#

    func testArrayIndexSegments() throws {
        XCTAssertEqual(try Item.decode(fromJSON: envelope, atPath: "data.items.1"), Item(id: "b", age: 0))
        XCTAssertEqual(try String.decode(fromJSON: envelope, atPath: "data.items.0.id"), "a")
        XCTAssertEqual(try Int.decode(fromJSON: envelope, atPath: "rows.1.0"), 3)
        XCTAssertEqual(try Item.decode(fromJSON: envelope, atPath: "data.0"), Item(id: "key", age: 0), "Digits on objects are keys")
        XCTAssertEqual(try Int.decode(fromJSON: "[[0,9]]", atPath: "0.1"), 9, "Root arrays are indexable")
        XCTAssertEqual(try [Int].decode(fromJSON: "[[0,9]]", atPath: "0"), [0, 9])
    }

    func testArrayIndexErrorsCarryFullPaths() throws {
        do {
            _ = try Item.decode(fromJSON: envelope, atPath: "data.items.5")
            XCTFail("Out of range must throw")
        } catch let DecodingError.valueNotFound(_, context) {
            XCTAssertEqual(context.codingPath.map(\.stringValue), ["data", "items", "Index 5"])
        }
        for path in ["data.items.x", "data.items.01", "rows.0.0.id", "data.items.-1"] {
            XCTAssertThrowsError(try Item.decode(fromJSON: envelope, atPath: path), path)
        }
        do {
            _ = try Int.decode(fromJSON: envelope, atPath: "data.missing.id")
            XCTFail("Missing intermediate key must throw")
        } catch let DecodingError.keyNotFound(key, context) {
            XCTAssertEqual(key.stringValue, "missing")
            XCTAssertEqual(context.codingPath.map(\.stringValue), ["data"])
        }
    }

    func testDiagnosticsThroughIndexSegmentsKeepArrayIndex() throws {
        let recorder = DiagnosticRecorder()
        _ = try recorder.coder().decode(Item.self, from: Data(envelope.utf8), atPath: "data.items.1")
        let entry = try XCTUnwrap(recorder.entries.first)
        XCTAssertEqual(entry.codingPath, ["data", "items", "Index 1", "age"])
        XCTAssertEqual(entry.arrayIndex, 1)
    }

    func testSnakeCasePresetAndPaths() throws {
        struct User: Codable, Equatable { let displayName: String }
        let coder = LYJSONCoder(configuration: .snakeCase)
        let json = Data(#"{"user_info":{"display_name":"n"}}"#.utf8)
        XCTAssertEqual(try coder.decode(User.self, from: json, atPath: "userInfo"), User(displayName: "n"))
        XCTAssertThrowsError(try coder.decode(User.self, from: json, atPath: "user_info"), "Paths match converted keys")
        XCTAssertTrue(try coder.encodeString(User(displayName: "n")).contains("display_name"))
    }

    func testDecodeWithDiagnosticsMatchesCallback() throws {
        let recorder = DiagnosticRecorder()
        let result = try recorder.coder().decodeWithDiagnostics(Item.self, from: Data(envelope.utf8), atPath: "data.items.1")
        XCTAssertEqual(result.value, Item(id: "b", age: 0))
        XCTAssertEqual(result.diagnostics, recorder.entries)
        XCTAssertEqual(result.diagnostics.map(\.reason), ["incompatible_value"])
        let clean = try LYJSONCoder().decodeWithDiagnostics(Item.self, from: Data(#"{"id":"a","age":1}"#.utf8))
        XCTAssertTrue(clean.diagnostics.isEmpty)
    }

    func testDecodeExpectingNoDiagnostics() throws {
        let coder = LYJSONCoder()
        XCTAssertEqual(try coder.decodeExpectingNoDiagnostics(Item.self, from: Data(envelope.utf8), atPath: "data.items.0"), Item(id: "a", age: 1))
        XCTAssertThrowsError(try coder.decodeExpectingNoDiagnostics([Item].self, from: Data(envelope.utf8), atPath: "data.items")) { error in
            let diagnostics = (error as? LYUnexpectedDiagnosticsError)?.diagnostics
            XCTAssertEqual(diagnostics?.map(\.codingPath), [["data", "items", "Index 1", "age"]])
        }
        XCTAssertThrowsError(try coder.decodeExpectingNoDiagnostics(Item.self, from: Data("{}".utf8))) { error in
            XCTAssertTrue(error is DecodingError, "Structural errors are thrown unchanged")
        }
    }
}
