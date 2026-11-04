import Foundation
import XCTest
@testable import TolerantCodable

private enum Role: String, Codable, LYUnknownCaseDecodable, Sendable {
    case owner, member, unknown

    static var unknownCase: Self {
        .unknown
    }
}

private struct Member: Codable, Equatable, Sendable {
    let id: String
    @LYDefault<LYDefaults.Int> var age: Int
    var role: Role

    init(id: String, age: Int, role: Role) {
        self.id = id
        self.age = age
        self.role = role
    }
}

final class ConversionTests: XCTestCase {
    private let envelope = #"{"code":0,"data":{"items":[{"id":"1","age":"30","role":"owner"},{"id":"2","role":"moderator"}],"next":null}}"#

    func testDecodeFromDataStringAndFoundationObjects() throws {
        let item = #"{"id":"1","age":30,"role":"owner"}"#
        let expected = Member(id: "1", age: 30, role: .owner)
        XCTAssertEqual(try Member.decode(fromJSON: item), expected)
        XCTAssertEqual(try Member.decode(fromJSON: Data(item.utf8)), expected)
        XCTAssertEqual(try Member.decode(fromJSONObject: ["id": "1", "age": "30", "role": "owner"]), expected)
        XCTAssertEqual(try [Member].decode(fromJSONObject: [["id": "1", "age": 30, "role": "owner"]]), [expected])
        XCTAssertThrowsError(try Member.decode(fromJSONObject: ["id": Date()]), "Invalid Foundation objects must throw")
        XCTAssertThrowsError(try Member.decode(fromJSON: #"{"age":1,"role":"owner"}"#), "Unwrapped fields stay strict")
    }

    func testDecodeAtPathWalksNestedObjectsInASinglePass() throws {
        let members = try [Member].decode(fromJSON: envelope, atPath: "data.items")
        XCTAssertEqual(members, [Member(id: "1", age: 30, role: .owner), Member(id: "2", age: 0, role: .unknown)])
        XCTAssertEqual(try Int.decode(fromJSON: envelope, atPath: "code"), 0)
        XCTAssertEqual(try [Member].decode(fromJSONObject: ["data": ["items": []]], atPath: "data.items"), [])
    }

    func testDecodeAtPathReportsFullPathsInDiagnosticsAndErrors() throws {
        let recorder = DiagnosticRecorder()
        _ = try recorder.coder().decode([Member].self, from: Data(envelope.utf8), atPath: "data.items")
        let paths = recorder.entries.map { $0.codingPath.joined(separator: ".") }
        XCTAssertEqual(paths, ["data.items.Index 0.age", "data.items.Index 1.age", "data.items.Index 1.role"])

        for path in ["data.missing", "code.items", "data..items", "."] {
            XCTAssertThrowsError(try [Member].decode(fromJSON: envelope, atPath: path), path)
        }
        do {
            _ = try [Member].decode(fromJSON: envelope, atPath: "data.missing")
        } catch let DecodingError.keyNotFound(key, context) {
            XCTAssertEqual(key.stringValue, "missing")
            XCTAssertEqual(context.codingPath.map(\.stringValue), ["data"])
        }
    }

    func testEncodeToDataStringAndFoundationObjects() throws {
        let member = Member(id: "1", age: 30, role: .member)
        let object = try XCTUnwrap(member.jsonObject() as? [String: Any])
        XCTAssertEqual(object["id"] as? String, "1")
        XCTAssertEqual(object["age"] as? Int, 30)
        XCTAssertEqual(object["role"] as? String, "member")
        XCTAssertEqual(try Member.decode(fromJSON: member.jsonData()), member)
        let pretty = try member.jsonString(prettyPrinted: true)
        XCTAssertTrue(pretty.contains("\n"))
        XCTAssertLessThan(try XCTUnwrap(pretty.range(of: "\"age\"")).lowerBound, try XCTUnwrap(pretty.range(of: "\"id\"")).lowerBound)
        let array = try XCTUnwrap(try [member].jsonObject() as? [[String: Any]])
        XCTAssertEqual(array.count, 1)
        XCTAssertEqual(array.first?["role"] as? String, "member")
        let scalar = try 42.jsonObject()
        XCTAssertEqual(scalar as? Int, 42)
    }
}
