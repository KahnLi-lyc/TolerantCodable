import SwiftUI
import TolerantCodable

/// 复刻 Socket 回调：首个参数可能是 String、Dictionary、Array 或 Data，一行解码并保留失败原因。
struct ConversionExample: View {
    private static let json = #"{"id":7,"text":"欢迎来到直播间 👋","senderLevel":"12"}"#

    /// 每次计算时现场构造载荷，避免把非 Sendable 的 Any 存为静态状态。
    private var payloads: [(String, Any?)] {
        [
            ("String", Self.json),
            ("[String: Any]", ["id": 7, "text": "字典载荷", "senderLevel": 3] as [String: Any]),
            ("Data", Data(Self.json.utf8)),
            ("NSDictionary", ["id": 8, "text": "NSDictionary"] as NSDictionary),
            ("nil", nil),
            ("Date", Date()),
            ("坏 JSON 文本", #"{"id":"#)
        ]
    }

    var body: some View {
        List {
            Section("ChatMessage.decode(fromAny:)") {
                ForEach(Array(payloads.enumerated()), id: \.offset) { _, payload in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payload.0).font(.caption.bold())
                        switch Result(catching: { try ChatMessage.decode(fromAny: payload.1) }) {
                        case let .success(message):
                            CodeBlock(text: "✅ id=\(message.id) text=\(message.text) level=\(message.senderLevel)")
                        case let .failure(error):
                            CodeBlock(text: "❌ \(describe(error))").foregroundStyle(.red)
                        }
                    }
                }
            }
            Section("模型 → 字典 → JSON 文本") {
                CodeBlock(text: roundTrip())
            }
            Section("LYJSONSerialization 带类型解析") {
                CodeBlock(text: typedParsing())
            }
        }
        .navigationTitle("Socket 载荷与互转")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func roundTrip() -> String {
        do {
            let message = ChatMessage(id: 1, text: "hi", senderLevel: 5)
            let dictionary = try message.jsonDictionary()
            let compact = try dictionary.lyJSONString(options: [.sortedKeys])
            let pretty = try Data(compact.utf8).lyPrettyJSONString()
            let entity = try message.converted(to: ChatMessageEntity.self)
            return """
            jsonDictionary()     \(dictionary.keys.sorted())
            lyJSONString()       \(compact)
            converted(to:)       ChatMessageEntity(id: \(entity.id), text: \(entity.text))
            lyPrettyJSONString()
            \(pretty)
            """
        } catch {
            return describe(error)
        }
    }

    private func typedParsing() -> String {
        func run(_ body: () throws -> [String: Any]) -> String {
            do {
                return try "\(body().count) key"
            } catch {
                return describe(error)
            }
        }
        return """
        parseObject({"a":1})  \(run { try LYJSONSerialization.parseObject(#"{"a":1}"#) })
        parseObject([1, 2])   \(run { try LYJSONSerialization.parseObject("[1, 2]") })
        """
    }
}
