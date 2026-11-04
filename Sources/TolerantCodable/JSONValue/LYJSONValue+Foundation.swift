import Foundation

public extension LYJSONValue {
    /// 从 Foundation JSON 对象构造，例如 JSONSerialization 的结果或 Socket 回调参数。
    /// 支持 NSNull、Bool、数字、String、数组、`[String: Any]` 及嵌套的 Optional；
    /// 非有限数字、非字符串键的字典和其他类型抛出 `LYConversionError.unsupportedValue`。
    init(any value: Any) throws {
        if let json = value as? LYJSONValue {
            self = json
            return
        }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            self = try mirror.children.first.map { try LYJSONValue(any: $0.value) } ?? .null
            return
        }
        switch value {
        case is NSNull:
            self = .null
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            self = try Self.number(number)
        case let array as [Any]:
            self = try .array(array.map(LYJSONValue.init(any:)))
        case let object as [String: Any]:
            self = try .object(object.mapValues(LYJSONValue.init(any:)))
        default:
            throw LYConversionError.unsupportedValue(typeName: String(reflecting: type(of: value)))
        }
    }

    /// 转回 Foundation JSON 对象：null 为 NSNull，数字为 NSNumber，可直接交给 JSONSerialization。
    var foundationObject: Any {
        switch self {
        case .null: NSNull()
        case let .bool(value): value
        case let .integer(value): NSNumber(value: value)
        case let .double(value): value
        case let .string(value): value
        case let .array(value): value.map(\.foundationObject)
        case let .object(value): value.mapValues(\.foundationObject) as [String: Any]
        }
    }

    private static func number(_ number: NSNumber) throws -> LYJSONValue {
        if lyIsBoolean(number) { return .bool(number.boolValue) }
        if let decimal = number as? NSDecimalNumber {
            let value = decimal.decimalValue
            guard !value.isNaN else { throw LYConversionError.unsupportedValue(typeName: "NaN") }
            // stringValue 是规范十进制文本；能被 Int64 完整解析即为范围内的整数。
            if let integer = Int64(decimal.stringValue) { return .integer(integer) }
            return .double(decimal.doubleValue)
        }
        if CFNumberIsFloatType(number) {
            let double = number.doubleValue
            guard double.isFinite else { throw LYConversionError.unsupportedValue(typeName: "non-finite Double") }
            return .double(double)
        }
        // 'Q' 类型的 UInt64 可能超出 Int64，直接读 int64Value 会溢出回绕。
        if String(cString: number.objCType) == "Q", number.uint64Value > UInt64(Int64.max) {
            return .double(Double(number.uint64Value))
        }
        return .integer(number.int64Value)
    }
}
