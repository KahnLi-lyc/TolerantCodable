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

    /// 从形态不确定的载荷解码（Data / String / 字典 / 数组 / LYJSONValue），适合 Socket 等回调参数；
    /// 归一化规则见 `LYJSONSerialization.data(fromAny:)`，nil 或不支持的类型直接抛错。
    static func decode(
        fromAny value: Any?,
        atPath path: String = "",
        coder: LYJSONCoder = LYJSONCoder(),
        context: LYCodingContext = .init()
    ) throws -> Self {
        try decode(fromJSON: LYJSONSerialization.data(fromAny: value), atPath: path, coder: coder, context: context)
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

    /// 编码为 `[String: Any]`；顶层不是对象时抛出 `LYConversionError.unexpectedRoot`。
    func jsonDictionary(coder: LYJSONCoder = LYJSONCoder()) throws -> [String: Any] {
        let object = try jsonObject(coder: coder)
        guard let dictionary = object as? [String: Any] else {
            throw LYConversionError.unexpectedRoot(expected: .object, actual: .init(foundation: object))
        }
        return dictionary
    }

    /// 编码为 `[Any]`；顶层不是数组时抛出 `LYConversionError.unexpectedRoot`。
    func jsonArray(coder: LYJSONCoder = LYJSONCoder()) throws -> [Any] {
        let object = try jsonObject(coder: coder)
        guard let array = object as? [Any] else {
            throw LYConversionError.unexpectedRoot(expected: .array, actual: .init(foundation: object))
        }
        return array
    }

    /// 编码为可跨并发边界传递的 LYJSONValue。
    func jsonValue(coder: LYJSONCoder = LYJSONCoder()) throws -> LYJSONValue {
        try JSONDecoder().decode(LYJSONValue.self, from: coder.encode(self))
    }

    /// 模型之间互转（例如 DTO → Entity）：用同一个 coder 编码再解码，兼容诊断照常收集，失败抛错。
    func converted<T: Decodable>(
        to type: T.Type = T.self,
        coder: LYJSONCoder = LYJSONCoder(),
        context: LYCodingContext = .init()
    ) throws -> T {
        try coder.decode(type, from: coder.encode(self), context: context)
    }
}
