import Foundation

// 标准库类型的 JSON 便捷方法，统一用 ly 前缀避免与业务扩展重名；全部委托 LYJSONSerialization，失败抛错。

public extension [String: Any] {
    /// 校验后序列化为 JSON 数据。
    func lyJSONData(options: JSONSerialization.WritingOptions = []) throws -> Data {
        try LYJSONSerialization.data(from: self, options: options)
    }

    /// 校验后序列化为 UTF-8 JSON 文本。
    func lyJSONString(options: JSONSerialization.WritingOptions = []) throws -> String {
        try LYJSONSerialization.string(from: self, options: options)
    }
}

public extension [Any] {
    /// 校验后序列化为 JSON 数据。
    func lyJSONData(options: JSONSerialization.WritingOptions = []) throws -> Data {
        try LYJSONSerialization.data(from: self, options: options)
    }

    /// 校验后序列化为 UTF-8 JSON 文本。
    func lyJSONString(options: JSONSerialization.WritingOptions = []) throws -> String {
        try LYJSONSerialization.string(from: self, options: options)
    }
}

public extension String {
    /// 解析为 Foundation JSON 对象；标量根节点需传入 fragmentsAllowed。
    func lyJSONObject(options: JSONSerialization.ReadingOptions = []) throws -> Any {
        try LYJSONSerialization.parse(self, options: options)
    }

    /// 解析为 `[String: Any]`；根节点不是对象时抛错。
    func lyJSONDictionary() throws -> [String: Any] {
        try LYJSONSerialization.parseObject(self)
    }

    /// 解析为 `[Any]`；根节点不是数组时抛错。
    func lyJSONArray() throws -> [Any] {
        try LYJSONSerialization.parseArray(self)
    }
}

public extension Data {
    /// 解析为 Foundation JSON 对象；标量根节点需传入 fragmentsAllowed。
    func lyJSONObject(options: JSONSerialization.ReadingOptions = []) throws -> Any {
        try LYJSONSerialization.parse(self, options: options)
    }

    /// 解析为 `[String: Any]`；根节点不是对象时抛错。
    func lyJSONDictionary() throws -> [String: Any] {
        try LYJSONSerialization.parseObject(self)
    }

    /// 解析为 `[Any]`；根节点不是数组时抛错。
    func lyJSONArray() throws -> [Any] {
        try LYJSONSerialization.parseArray(self)
    }

    /// 重新排版为缩进、排序键的 JSON 文本，用于日志与调试；非法 JSON 抛错。
    func lyPrettyJSONString() throws -> String {
        let object = try LYJSONSerialization.parse(self, options: .fragmentsAllowed)
        return try LYJSONSerialization.string(
            from: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        )
    }
}
