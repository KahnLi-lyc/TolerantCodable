import Foundation
import XCTest
@testable import TolerantCodable

final class JSONValueTests: XCTestCase {
    private let sample = #"{"flag":true,"one":1,"ratio":1.5,"name":"n","none":null,"list":[1,"a",{"k":false}],"obj":{"0":"zero"}}"#

    func testDecodingKeepsKindsApartAndRoundTrips() throws {
        let value = try JSONDecoder().decode(LYJSONValue.self, from: Data(sample.utf8))
        XCTAssertEqual(value["flag"], .bool(true))
        XCTAssertEqual(value["one"], .integer(1))
        XCTAssertEqual(value["ratio"], .double(1.5))
        XCTAssertEqual(value["name"], "n")
        XCTAssertEqual(value["none"], .null)
        XCTAssertEqual(value["list"], [1, "a", ["k": false]])
        XCTAssertEqual(try JSONDecoder().decode(LYJSONValue.self, from: JSONEncoder().encode(value)), value)
        XCTAssertEqual(try JSONDecoder().decode(LYJSONValue.self, from: Data("18446744073709551615".utf8)).kind, .number)
        XCTAssertEqual(value.description.first, "{")
    }

    func testAccessorsAndPathSubscript() throws {
        let value = try JSONDecoder().decode(LYJSONValue.self, from: Data(sample.utf8))
        XCTAssertEqual(value[path: "list.2.k"], false)
        XCTAssertEqual(value[path: "obj.0"], "zero", "Digits on objects are keys")
        XCTAssertEqual(value[path: ""], value)
        for path in ["list.3", "list.01", "list.-1", "list..1", "name.x", "missing"] {
            XCTAssertNil(value[path: path], path)
        }
        XCTAssertEqual(value["one"]?.int64Value, 1)
        XCTAssertEqual(value["one"]?.doubleValue, 1)
        XCTAssertNil(value["one"]?.stringValue)
        XCTAssertNil(value["name"]?.int64Value)
        XCTAssertEqual(value["list"]?[1], "a")
        XCTAssertNil(value["list"]?[9])
        XCTAssertNil(value[0])
        XCTAssertTrue(value["none"]?.isNull == true)
        XCTAssertEqual(value["obj"]?.objectValue?.count, 1)
        XCTAssertEqual(value["list"]?.arrayValue?.count, 3)
        XCTAssertEqual(value["flag"]?.boolValue, true)
    }

    func testFoundationBridging() throws {
        let foundation = try LYJSONSerialization.parse(Data(sample.utf8))
        let value = try LYJSONValue(any: foundation)
        XCTAssertEqual(value, try JSONDecoder().decode(LYJSONValue.self, from: Data(sample.utf8)))
        XCTAssertEqual(try LYJSONValue(any: NSNumber(value: true)), .bool(true))
        XCTAssertEqual(try LYJSONValue(any: NSNumber(value: 1)), .integer(1))
        XCTAssertEqual(try LYJSONValue(any: UInt64.max), .double(Double(UInt64.max)))
        XCTAssertEqual(try LYJSONValue(any: XCTUnwrap(Decimal(string: "12"))), .integer(12))
        XCTAssertEqual(try LYJSONValue(any: XCTUnwrap(Decimal(string: "1.5"))), .double(1.5))
        let optionals: [String: Any?] = ["a": nil, "b": 1]
        XCTAssertEqual(try LYJSONValue(any: optionals), ["a": .null, "b": 1])
        XCTAssertThrowsError(try LYJSONValue(any: Double.nan))
        XCTAssertThrowsError(try LYJSONValue(any: [1: "int key"]))
        XCTAssertThrowsError(try LYJSONValue(any: Date())) { error in
            XCTAssertEqual(error as? LYConversionError, .unsupportedValue(typeName: "Foundation.Date"))
        }
        let back = try XCTUnwrap(value.foundationObject as? [String: Any])
        XCTAssertTrue(back["none"] is NSNull)
        XCTAssertEqual(try LYJSONValue(any: back), value)
        XCTAssertNoThrow(try LYJSONSerialization.data(from: value.foundationObject))
    }

    func testDecodeModelsAndUseAsField() throws {
        struct Event: Codable, Equatable {
            let type: String
            let payload: LYJSONValue
        }
        let event = try Event.decode(fromJSON: #"{"type":"gift","payload":{"count":3,"to":["a"]}}"#)
        XCTAssertEqual(event.payload[path: "to.0"], "a")
        XCTAssertEqual(try event.payload.decode(Int.self, atPath: "count"), 3)
        XCTAssertEqual(try Event.decode(fromJSON: event.jsonData()), event)
        XCTAssertThrowsError(try Event.decode(fromJSON: #"{"type":"gift"}"#), "LYJSONValue fields are strict")
    }
}
