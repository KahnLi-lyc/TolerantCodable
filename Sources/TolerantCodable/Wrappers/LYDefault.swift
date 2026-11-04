import Foundation

/// 为 LYDefault 声明缺失、null 或无法兼容时的默认值。
public protocol LYDefaultValueProvider {
    /// 字段解码后的值类型。
    associatedtype Value: Decodable
    /// 默认值；应为稳定、无副作用的值。
    static var defaultValue: Value { get }
}

/// 常用默认值提供者，也可由业务 DTO 自行实现 LYDefaultValueProvider。
public enum LYDefaults {
    /// 空字符串。
    public enum String: LYDefaultValueProvider {
        /// 字段的空字符串。
        public static var defaultValue: Swift.String {
            ""
        }
    }

    /// Int 零值。
    public enum Int: LYDefaultValueProvider {
        /// 字段的Int 零值。
        public static var defaultValue: Swift.Int {
            0
        }
    }

    /// Int64 零值。
    public enum Int64: LYDefaultValueProvider {
        /// 字段的Int64 零值。
        public static var defaultValue: Swift.Int64 {
            0
        }
    }

    /// Double 零值。
    public enum Double: LYDefaultValueProvider {
        /// 字段的Double 零值。
        public static var defaultValue: Swift.Double {
            0
        }
    }

    /// Float 零值。
    public enum Float: LYDefaultValueProvider {
        /// 字段的Float 零值。
        public static var defaultValue: Swift.Float {
            0
        }
    }

    /// Decimal 零值。
    public enum Decimal: LYDefaultValueProvider {
        /// 字段的Decimal 零值。
        public static var defaultValue: Foundation.Decimal {
            0
        }
    }

    /// false 默认值。
    public enum False: LYDefaultValueProvider {
        /// 字段的false 默认值。
        public static var defaultValue: Bool {
            false
        }
    }

    /// true 默认值。
    public enum True: LYDefaultValueProvider {
        /// 字段的true 默认值。
        public static var defaultValue: Bool {
            true
        }
    }

    /// 空数组；元素仍按其自身的 Decodable 契约严格解码。
    public enum EmptyArray<Element: Decodable>: LYDefaultValueProvider {
        /// 空数组默认值。
        public static var defaultValue: [Element] {
            []
        }
    }

    /// 空字典；键和值仍按其自身的 Decodable 契约严格解码。
    public enum EmptyDictionary<Key: Decodable & Hashable, Value: Decodable>: LYDefaultValueProvider {
        /// 空字典默认值。
        public static var defaultValue: [Key: Value] {
            [:]
        }
    }
}

/// 显式选择“直接解码 → 标量转换 → 默认值”的字段包装器。
@propertyWrapper
public struct LYDefault<Provider: LYDefaultValueProvider>: Decodable {
    /// 解码后的值，可由调用方修改。
    public var wrappedValue: Provider.Value

    /// 使用 provider 默认值创建字段。
    public init() {
        wrappedValue = Provider.defaultValue
    }

    /// 使用显式初始值创建字段，供代码构造模型使用。
    /// 属性声明处的初始值（如 `= 5`）不参与解码；缺失或无法兼容时始终回退 `Provider.defaultValue`。
    public init(wrappedValue: Provider.Value) {
        self.wrappedValue = wrappedValue
    }

    /// 原生 JSONDecoder 也支持兼容解码；诊断仅在注入 LYDiagnosticSink 时收集。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let direct = try? container.decode(Provider.Value.self), lyIsFinite(direct) {
            wrappedValue = direct
        } else if let converted: Provider.Value = lyConvert(container) {
            wrappedValue = converted
            decoder.lyRecord(.conversion, target: Provider.Value.self, reason: "compatible_scalar")
        } else {
            wrappedValue = Provider.defaultValue
            decoder.lyRecord(
                .fallback,
                target: Provider.Value.self,
                reason: container.decodeNil() ? "null_value" : "incompatible_value"
            )
        }
    }
}

extension LYDefault: Encodable where Provider.Value: Encodable {
    /// 按实际值编码，不输出包装器结构。
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension LYDefault: Equatable where Provider.Value: Equatable {}
extension LYDefault: Hashable where Provider.Value: Hashable {}
extension LYDefault: Sendable where Provider.Value: Sendable {}

public extension KeyedDecodingContainer {
    /// 让合成 Decodable 在字段缺失时也采用 provider 的默认值。
    func decode<Provider>(_ type: LYDefault<Provider>.Type, forKey key: Key) throws -> LYDefault<Provider> {
        guard contains(key) else {
            if let decoder = try? superDecoder(forKey: key) {
                decoder.lyRecord(.fallback, target: Provider.Value.self, reason: "missing_key")
            }
            return LYDefault()
        }
        // 快速路径：类型正确时直接解码，跳过 superDecoder 与单值容器；失败再走兼容路径并记录诊断。
        if let direct = try? decode(Provider.Value.self, forKey: key), lyIsFinite(direct) {
            return LYDefault(wrappedValue: direct)
        }
        return try LYDefault(from: superDecoder(forKey: key))
    }
}

/// 拒绝非有限数字，避免兼容策略把 NaN / infinity 带入业务模型。
private func lyIsFinite(_ value: some Any) -> Bool {
    if let value = value as? Double { return value.isFinite }
    if let value = value as? Float { return value.isFinite }
    if let value = value as? Decimal { return !value.isNaN }
    return true
}

/// Decimal(string:) 会接受数字前缀，因此先验证完整十进制语法。
func lyDecimal(_ text: String) -> Decimal? {
    guard text
        .range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
        let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN
    else { return nil }
    return value
}

/// 整数转换始终走 Decimal，保留 Int64 高位并在截断后检查边界。
private func lyInteger<T: FixedWidthInteger>(_ value: Decimal, _: T.Type) -> T? {
    var source = value
    var rounded = Decimal()
    NSDecimalRound(&rounded, &source, 0, value < 0 ? .up : .down)
    guard let minimum = Decimal(string: String(T.min)), let maximum = Decimal(string: String(T.max)),
          rounded >= minimum, rounded <= maximum
    else { return nil }
    return T(NSDecimalNumber(decimal: rounded).stringValue)
}

/// 只兼容明确支持的基础标量；数组、字典和自定义模型不会被递归宽松转换。
private func lyConvert<Value>(_ container: any SingleValueDecodingContainer) -> Value? {
    let text = (try? container.decode(String.self))?.trimmingCharacters(in: .whitespacesAndNewlines)
    if Value.self == String.self {
        if let value = try? container.decode(Int64.self) { return String(value) as? Value }
        if let value = try? container.decode(UInt64.self) { return String(value) as? Value }
        if let value = try? container.decode(Decimal.self), !value.isNaN {
            return NSDecimalNumber(decimal: value).stringValue as? Value
        }
        if let value = try? container.decode(Bool.self) { return (value ? "true" : "false") as? Value }
        return nil
    }
    if Value.self == Bool.self {
        if let text {
            switch text.lowercased() {
            case "true", "1": return true as? Value
            case "false", "0": return false as? Value
            default: return nil
            }
        }
        if let integer = try? container.decode(Int64.self) { return (integer != 0) as? Value }
        return nil
    }
    let decimal = text.flatMap(lyDecimal) ?? (text == nil ? try? container.decode(Decimal.self) : nil)
    if Value.self == Decimal.self { return decimal as? Value }
    if Value.self == Int.self { return decimal.flatMap { lyInteger($0, Int.self) } as? Value }
    if Value.self == Int64.self { return decimal.flatMap { lyInteger($0, Int64.self) } as? Value }
    // 浮点文本与整数共用严格十进制语法，拒绝 0x、nan、inf 等 Swift 特有写法。
    let decimalText = text.flatMap { lyDecimal($0) == nil ? nil : $0 }
    if Value.self == Double.self {
        let number = text == nil ? try? container.decode(Double.self) : decimalText.flatMap(Double.init)
        return number.flatMap { $0.isFinite ? $0 : nil } as? Value
    }
    if Value.self == Float.self {
        let number = text == nil ? try? container.decode(Float.self) : decimalText.flatMap(Float.init)
        return number.flatMap { $0.isFinite ? $0 : nil } as? Value
    }
    return nil
}
