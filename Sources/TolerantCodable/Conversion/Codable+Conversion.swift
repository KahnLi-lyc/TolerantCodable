import Foundation

// 模型与 JSON 各种形态之间的便捷转换。所有方法失败时抛错，不返回 nil，调用方可以拿到真实原因。

public extension Decodable {
    /// 从 JSON 数据解码；`path` 非空时只解码该路径指向的子节点，例如 `"data.items"`。
    static func decode(
        fromJSON data: Data,
        atPath path: String = "",
        coder: LYJSONCoder = LYJSONCoder(),
        context: LYCodingContext = .init()
    ) throws -> Self {
        try coder.decode(Self.self, from: data, atPath: path, context: context)
    }

    /// 从 UTF-8 JSON 文本解码。
    static func decode(
        fromJSON string: String,
        atPath path: String = "",
        coder: LYJSONCoder = LYJSONCoder(),
        context: LYCodingContext = .init()
    ) throws -> Self {
        try decode(fromJSON: Data(string.utf8), atPath: path, coder: coder, context: context)
    }

    /// 从 Foundation JSON 对象（`[String: Any]`、`[Any]` 等）解码；对象先经合法性校验再序列化，非法对象直接抛错。
    static func decode(
        fromJSONObject object: Any,
        atPath path: String = "",
        coder: LYJSONCoder = LYJSONCoder(),
        context: LYCodingContext = .init()
    ) throws -> Self {
        try decode(fromJSON: LYJSONSerialization.data(from: object), atPath: path, coder: coder, context: context)
    }
}

public extension Encodable {
    /// 编码为 JSON 数据。
    func jsonData(coder: LYJSONCoder = LYJSONCoder()) throws -> Data {
        try coder.encode(self)
    }

    /// 编码为 UTF-8 JSON 文本；`prettyPrinted` 同时排序键，便于对比与调试。
    func jsonString(prettyPrinted: Bool = false, coder: LYJSONCoder = LYJSONCoder()) throws -> String {
        try coder.encodeString(self, prettyPrinted: prettyPrinted)
    }

    /// 编码为 Foundation JSON 对象：对象得到 `[String: Any]`，数组得到 `[Any]`，标量顶层得到对应的 Foundation 值。
    func jsonObject(coder: LYJSONCoder = LYJSONCoder()) throws -> Any {
        try LYJSONSerialization.parse(coder.encode(self), options: .fragmentsAllowed)
    }
}
