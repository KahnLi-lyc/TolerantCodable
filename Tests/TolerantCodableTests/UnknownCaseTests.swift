import Foundation
import XCTest
@testable import TolerantCodable

private enum SampleState: String, Codable, CaseIterable, LYUnknownCaseDecodable, Sendable {
    case active
    case closed = "closed_by_owner"
    case unknown

    static var unknownCase: Self {
        .unknown
    }
}

private enum SampleLevel: Int, Codable, LYUnknownCaseDecodable, Sendable {
    case low = 1
    case high = 2
    case unknown = -1

    static var unknownCase: Self {
        .unknown
    }
}

private struct SampleModel: Codable, Equatable {
    var state: SampleState
    var optionalState: SampleState?
    var level: SampleLevel
}

private struct HandWrittenModel: Decodable {
    let states: [SampleState]

    private enum CodingKeys: String, CodingKey { case states }

    init(from decoder: Decoder) throws {
        states = try decoder.container(keyedBy: CodingKeys.self).decode([SampleState].self, forKey: .states)
    }
}

final class UnknownCaseTests: XCTestCase {
    func testKnownValuesDecodeAndUnrecognizedValuesFallBackWithoutFailingTheModel() throws {
        let known = try decode(#"{"state":"closed_by_owner","optionalState":"active","level":2}"#)
        XCTAssertEqual(known, SampleModel(state: .closed, optionalState: .active, level: .high))

        let unknown = try decode(#"{"state":"archived","optionalState":"frozen","level":9}"#)
        XCTAssertEqual(unknown, SampleModel(state: .unknown, optionalState: .unknown, level: .unknown))
        XCTAssertFalse(unknown.state.isKnown)

        let absent = try decode(#"{"state":"active","optionalState":null,"level":1}"#)
        XCTAssertNil(absent.optionalState)
    }

    func testStructuralErrorsStayStrict() {
        let invalid = [
            #"{"state":1,"level":1}"#,
            #"{"state":null,"level":1}"#,
            #"{"level":1}"#,
            #"{"state":"active","level":"1"}"#,
            #"{"state":"active","optionalState":false,"level":1}"#
        ]
        for json in invalid {
            XCTAssertThrowsError(try decode(json), json)
        }
    }

    func testHandWrittenDecodersAndArraysUseTheFallback() throws {
        let model = try JSONDecoder().decode(HandWrittenModel.self, from: Data(#"{"states":["active","new_value"]}"#.utf8))
        XCTAssertEqual(model.states, [.active, .unknown])
    }

    func testDiagnosticsNameTypeAndPathButNotTheRawValue() throws {
        let recorder = DiagnosticRecorder()
        _ = try recorder.coder().decode(SampleModel.self, from: Data(#"{"state":"secret-token","optionalState":"active","level":9}"#.utf8))
        let entries = recorder.entries
        XCTAssertEqual(entries.map(\.codingPath), [["state"], ["level"]])
        XCTAssertTrue(entries.allSatisfy { $0.kind == .fallback && $0.reason == "unknown_enum_case" })
        XCTAssertTrue(entries[0].targetType.hasSuffix("SampleState"), entries[0].targetType)
        XCTAssertFalse("\(entries)".contains("secret-token"))
    }

    func testSinkCanBeInjectedIntoANativeDecoder() throws {
        let collector = LYDiagnosticCollector(limit: 1)
        let decoder = JSONDecoder()
        decoder.userInfo[.lyDiagnostics] = collector
        let model = try decoder.decode([SampleState].self, from: Data(#"["active","x","y","z"]"#.utf8))
        XCTAssertEqual(model, [.active, .unknown, .unknown, .unknown])
        let diagnostics = collector.diagnostics
        XCTAssertEqual(diagnostics.count, 2)
        XCTAssertEqual(diagnostics[0].arrayIndex, 1)
        XCTAssertEqual(diagnostics[1].kind, .suppressed)
        XCTAssertEqual(diagnostics[1].reason, "2")
        _ = try JSONDecoder().decode([SampleState].self, from: Data(#"["x"]"#.utf8))
    }

    func testKnownCasesExcludeTheFallbackAndEncodingKeepsRawValues() throws {
        XCTAssertEqual(SampleState.knownCases, [.active, .closed])
        let data = try JSONEncoder().encode(SampleModel(state: .unknown, optionalState: nil, level: .unknown))
        XCTAssertEqual(try decode(String(decoding: data, as: UTF8.self)), SampleModel(state: .unknown, optionalState: nil, level: .unknown))
    }

    private func decode(_ json: String) throws -> SampleModel {
        try JSONDecoder().decode(SampleModel.self, from: Data(json.utf8))
    }
}
