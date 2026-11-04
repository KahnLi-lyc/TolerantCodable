import Foundation

/// 类型不符时得到 nil 而不是让整个模型失败；缺失和 null 是 Optional 的正常语义，不记录诊断。
@propertyWrapper
public struct LYLossyOptional<Value: Decodable>: Decodable {
    /// 解码后的值；类型不符时为 nil。
    public var wrappedValue: Value?

    /// 默认值为 nil。
    public init(wrappedValue: Value? = nil) {
        self.wrappedValue = wrappedValue
    }

    /// null 静默为 nil；其他无法解码的值记录 `incompatible_value` 后为 nil。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            wrappedValue = nil
            return
        }
        do {
            wrappedValue = try container.decode(Value.self)
        } catch {
            wrappedValue = nil
            decoder.lyRecord(.fallback, target: Value.self, reason: "incompatible_value")
        }
    }
}

extension LYLossyOptional: Encodable where Value: Encodable {
    /// 单独编码时 nil 写为 null；作为模型字段时由 KeyedEncodingContainer 重载省略该键。
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue { try container.encode(wrappedValue) } else { try container.encodeNil() }
    }
}

extension LYLossyOptional: Equatable where Value: Equatable {}
extension LYLossyOptional: Hashable where Value: Hashable {}
extension LYLossyOptional: Sendable where Value: Sendable {}

public extension KeyedDecodingContainer {
    /// 合成 Decodable 缺少字段时为 nil，不记录诊断。
    func decode<Value>(_ type: LYLossyOptional<Value>.Type, forKey key: Key) throws -> LYLossyOptional<Value> {
        guard contains(key) else { return LYLossyOptional() }
        // 快速路径：null 或类型正确时直接解码；失败再走兼容路径并记录诊断。
        do {
            return try LYLossyOptional(wrappedValue: decodeIfPresent(Value.self, forKey: key))
        } catch {
            return try LYLossyOptional(from: superDecoder(forKey: key))
        }
    }
}

public extension KeyedEncodingContainer {
    /// 与原生 Optional 一致：值为 nil 时省略该键。
    mutating func encode(_ value: LYLossyOptional<some Encodable>, forKey key: Key) throws {
        try encodeIfPresent(value.wrappedValue, forKey: key)
    }
}
