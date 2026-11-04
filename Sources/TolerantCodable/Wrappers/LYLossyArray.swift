import Foundation

/// 保留可解码元素并丢弃坏元素；缺失、null 或非数组值回退为空数组。
@propertyWrapper
public struct LYLossyArray<Element: Decodable>: Decodable {
    /// 按服务端顺序保留的有效元素。
    public var wrappedValue: [Element]

    /// 默认创建空数组。
    public init(wrappedValue: [Element] = []) {
        self.wrappedValue = wrappedValue
    }

    /// 每轮先取得 superDecoder 推进索引，避免失败元素导致死循环。
    public init(from decoder: any Decoder) throws {
        guard var container = try? decoder.unkeyedContainer() else {
            wrappedValue = []
            let isNull = (try? decoder.singleValueContainer().decodeNil()) == true
            decoder.lyRecord(.fallback, target: [Element].self, reason: isNull ? "null_value" : "expected_array")
            return
        }
        var elements: [Element] = []
        while !container.isAtEnd {
            let elementDecoder = try container.superDecoder()
            do {
                // 通过容器调用保留 JSONDecoder 对 Date/Data 的策略拦截。
                try elements.append(elementDecoder.singleValueContainer().decode(Element.self))
            } catch {
                elementDecoder.lyRecord(.discard, target: Element.self, reason: "invalid_array_element")
            }
        }
        wrappedValue = elements
    }
}

extension LYLossyArray: Encodable where Element: Encodable {
    /// 仅编码有效元素。
    public func encode(to encoder: any Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}

extension LYLossyArray: Equatable where Element: Equatable {}
extension LYLossyArray: Hashable where Element: Hashable {}
extension LYLossyArray: Sendable where Element: Sendable {}

public extension KeyedDecodingContainer {
    /// 合成 Decodable 遇到缺失字段时回退为空数组。
    func decode<Element>(_ type: LYLossyArray<Element>.Type, forKey key: Key) throws -> LYLossyArray<Element> {
        guard contains(key) else {
            if let decoder = try? superDecoder(forKey: key) {
                decoder.lyRecord(.fallback, target: [Element].self, reason: "missing_key")
            }
            return LYLossyArray()
        }
        // 快速路径：整组元素都合法时直接解码；任一元素失败再逐个解码并丢弃坏元素。
        if let direct = try? decode([Element].self, forKey: key) {
            return LYLossyArray(wrappedValue: direct)
        }
        return try LYLossyArray(from: superDecoder(forKey: key))
    }
}
