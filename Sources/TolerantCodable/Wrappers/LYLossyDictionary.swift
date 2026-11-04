import Foundation

/// 保留可解码的键值对并丢弃坏条目；缺失、null 或非对象值回退为空字典。
/// 键按 JSON 原文转换（不受 keyDecodingStrategy 影响，与原生 `[String: V]` 一致），无法转换的键同样丢弃。
@propertyWrapper
public struct LYLossyDictionary<Key: Hashable & LosslessStringConvertible, Value: Decodable>: Decodable {
    /// 有效条目。
    public var wrappedValue: [Key: Value]

    /// 默认创建空字典。
    public init(wrappedValue: [Key: Value] = [:]) {
        self.wrappedValue = wrappedValue
    }

    /// 借助原生 `[String: Entry]` 解码保留原始键；Entry 自身从不抛错，坏条目以诊断记录后丢弃。
    public init(from decoder: any Decoder) throws {
        guard let entries = try? decoder.singleValueContainer().decode([String: LYLossyDictionaryEntry<Key, Value>].self) else {
            wrappedValue = [:]
            let isNull = (try? decoder.singleValueContainer().decodeNil()) == true
            decoder.lyRecord(.fallback, target: [Key: Value].self, reason: isNull ? "null_value" : "expected_object")
            return
        }
        var result: [Key: Value] = [:]
        for (raw, entry) in entries {
            if let key = Key(raw), let value = entry.value { result[key] = value }
        }
        wrappedValue = result
    }

    /// 从已按原始键解码的字典构造；任一键无法转换时返回 nil，交给兼容路径逐条处理。
    fileprivate init?(raw: [String: Value]) {
        var result: [Key: Value] = [:]
        for (raw, value) in raw {
            guard let key = Key(raw) else { return nil }
            result[key] = value
        }
        wrappedValue = result
    }
}

/// 单个条目的解码结果；用 Optional 包一层区分"值为 nil"与"条目被丢弃"。
struct LYLossyDictionaryEntry<Key: LosslessStringConvertible, Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        guard let raw = decoder.codingPath.last?.stringValue, Key(raw) != nil else {
            value = nil
            decoder.lyRecord(.discard, target: Key.self, reason: "invalid_dictionary_key")
            return
        }
        do {
            value = try .some(decoder.singleValueContainer().decode(Value.self))
        } catch {
            value = nil
            decoder.lyRecord(.discard, target: Value.self, reason: "invalid_dictionary_value")
        }
    }
}

extension LYLossyDictionary: Encodable where Value: Encodable {
    /// 以 `key.description` 作为 JSON 键编码，保证可以往返。
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: LYAnyKey.self)
        for (key, value) in wrappedValue {
            try container.encode(value, forKey: LYAnyKey(key.description))
        }
    }
}

extension LYLossyDictionary: Equatable where Value: Equatable {}
extension LYLossyDictionary: Hashable where Value: Hashable {}
extension LYLossyDictionary: Sendable where Key: Sendable, Value: Sendable {}

public extension KeyedDecodingContainer {
    /// 合成 Decodable 遇到缺失字段时回退为空字典。
    func decode<DictKey, Value>(
        _ type: LYLossyDictionary<DictKey, Value>.Type,
        forKey key: Key
    ) throws -> LYLossyDictionary<DictKey, Value> {
        guard contains(key) else {
            if let decoder = try? superDecoder(forKey: key) {
                decoder.lyRecord(.fallback, target: [DictKey: Value].self, reason: "missing_key")
            }
            return LYLossyDictionary()
        }
        // 快速路径：整组条目都合法时直接解码；任一键或值失败再逐条处理并记录诊断。
        if let direct = try? decode([String: Value].self, forKey: key), let value = LYLossyDictionary<DictKey, Value>(raw: direct) {
            return value
        }
        return try LYLossyDictionary(from: superDecoder(forKey: key))
    }
}
