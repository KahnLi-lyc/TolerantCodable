import Foundation

/// 宽松标量转换，规则与 `@LYDefault` 的兼容白名单一致（由 ScalarTests 的等价性测试保证）：
/// - 文本先去掉首尾空白，再按严格十进制语法解析，拒绝 `0x10`、`nan`、`inf`；
/// - 整数经 Decimal 向零截断并检查边界；
/// - Bool 只接受 `true` / `false` / `1` / `0`（不区分大小写）及整数（非零为 true）；
/// - 数字和 Bool 可转为 String；String 目标对文本不做 trim。
///
/// 输入可以是 Foundation 值（JSONSerialization 结果、Socket 参数）或 `LYJSONValue`。
/// 失败抛出 `LYConversionError`，不返回 nil 吞掉原因。
public enum LYScalar {
    /// 转为 String。
    public static func string(from value: Any?) throws -> String {
        let json = try input(value)
        switch json {
        case let .string(text): return text
        case let .integer(integer): return String(integer)
        case let .bool(flag): return flag ? "true" : "false"
        case let .double(number):
            if let decimal = lyDecimal(fromDouble: number) { return NSDecimalNumber(decimal: decimal).stringValue }
        default: break
        }
        throw incompatible(String.self, json)
    }

    /// 转为 Bool。
    public static func bool(from value: Any?) throws -> Bool {
        let json = try input(value)
        switch json {
        case let .bool(flag): return flag
        case let .integer(integer): return integer != 0
        case let .double(number):
            if let integer = Int64(exactly: number) { return integer != 0 }
        case let .string(text):
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: break
            }
        default: break
        }
        throw incompatible(Bool.self, json)
    }

    /// 转为 Int；小数向零截断，超出范围抛错。
    public static func int(from value: Any?) throws -> Int {
        let json = try input(value)
        guard let result = decimal(json).flatMap({ lyInteger($0, Int.self) }) else { throw incompatible(Int.self, json) }
        return result
    }

    /// 转为 Int64；小数向零截断，超出范围抛错。
    public static func int64(from value: Any?) throws -> Int64 {
        let json = try input(value)
        guard let result = decimal(json).flatMap({ lyInteger($0, Int64.self) }) else { throw incompatible(Int64.self, json) }
        return result
    }

    /// 转为 Decimal。
    public static func decimal(from value: Any?) throws -> Decimal {
        let json = try input(value)
        guard let result = decimal(json) else { throw incompatible(Decimal.self, json) }
        return result
    }

    /// 转为 Double；结果必须有限。
    public static func double(from value: Any?) throws -> Double {
        let json = try input(value)
        let result: Double? = switch json {
        case let .integer(integer): Double(integer)
        case let .double(number): number
        case let .string(text): strictText(text).flatMap(Double.init)
        default: nil
        }
        guard let result, result.isFinite else { throw incompatible(Double.self, json) }
        return result
    }

    /// 转为 Float；结果必须有限。
    public static func float(from value: Any?) throws -> Float {
        let json = try input(value)
        let result: Float? = switch json {
        case let .integer(integer): Float(integer)
        case let .double(number): Float(number)
        case let .string(text): strictText(text).flatMap(Float.init)
        default: nil
        }
        guard let result, result.isFinite else { throw incompatible(Float.self, json) }
        return result
    }

    // MARK: - Helpers

    private static func input(_ value: Any?) throws -> LYJSONValue {
        guard let value else { return .null }
        return try LYJSONValue(any: value)
    }

    private static func decimal(_ json: LYJSONValue) -> Decimal? {
        switch json {
        case let .integer(integer): Decimal(integer)
        case let .double(number): lyDecimal(fromDouble: number)
        case let .string(text): lyDecimal(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default: nil
        }
    }

    /// 去掉首尾空白后只返回通过严格十进制语法的文本。
    private static func strictText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return lyDecimal(trimmed) == nil ? nil : trimmed
    }

    private static func incompatible(_ target: Any.Type, _ json: LYJSONValue) -> LYConversionError {
        .incompatibleScalar(target: String(reflecting: target), source: json.kind)
    }
}

/// Double 的最短十进制表示转 Decimal，避免 `Decimal(3.7)` 引入二进制误差。
func lyDecimal(fromDouble value: Double) -> Decimal? {
    guard value.isFinite else { return nil }
    return lyDecimal(String(value))
}
