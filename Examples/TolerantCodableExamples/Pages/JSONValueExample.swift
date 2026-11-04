import SwiftUI
import TolerantCodable

/// 动态 payload：用 LYJSONValue 承载，按路径取值，再按需宽松转换或解码为模型。
struct JSONValueExample: View {
    private struct Query: Identifiable {
        let id = UUID()
        let code: String
        let result: String
    }

    var body: some View {
        List {
            Section("输入 event.json") { CodeBlock(text: Samples.text("event")) }
            switch Result(catching: { try LiveEvent.decode(fromJSON: Samples.data("event")) }) {
            case let .success(event):
                Section("查询") {
                    ForEach(queries(event.payload)) { query in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(query.code).font(.caption.monospaced())
                            Text(query.result).font(.caption.monospaced().bold())
                        }
                    }
                }
            case let .failure(error):
                Section("错误") { CodeBlock(text: describe(error)) }
            }
        }
        .navigationTitle("LYJSONValue")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func queries(_ payload: LYJSONValue) -> [Query] {
        func run(_ code: String, _ body: () throws -> Any?) -> Query {
            let result: String
            do {
                result = try body().map { "\($0)" } ?? "nil"
            } catch {
                result = "❌ \(describe(error))"
            }
            return Query(code: code, result: result)
        }
        return [
            run(#"payload[path: "sender.name"]"#) { payload[path: "sender.name"] },
            run(#"payload[path: "combo.2"]"#) { payload[path: "combo.2"] },
            run(#"payload["count"]?.int64Value  // 精确访问"#) { payload["count"]?.int64Value },
            run(#"LYScalar.int(from: payload["count"])  // 宽松转换"#) { try LYScalar.int(from: payload["count"]) },
            run(#"LYScalar.bool(from: payload[path: "sender.vip"])"#) { try LYScalar.bool(from: payload[path: "sender.vip"]) },
            run(#"LYScalar.int(from: payload["extra"])"#) { try LYScalar.int(from: payload["extra"]) },
            run("payload.decode(Gift.self)") {
                let gift = try payload.decode(Gift.self)
                return "Gift(giftId: \(gift.giftId), count: \(gift.count))"
            },
            run("payload.foundationObject → lyJSONString") {
                try (payload.foundationObject as? [String: Any])?.lyJSONString(options: [.sortedKeys])
            }
        ]
    }
}
