import Foundation

/// 转换工具的受控错误；只携带类型名和 JSON 种类，不包含原始值。
public enum LYConversionError: Error, Sendable, Equatable {
    /// JSON 值的种类，用于描述期望与实际的差异。
    public enum Kind: String, Sendable, CustomStringConvertible {
        case object, array, string, number, bool, null, other

        /// 简短名称，例如 `null`，便于日志阅读。
        public var description: String {
            rawValue
        }
    }

    /// 根节点种类不符，例如 parseObject 拿到数组。
    case unexpectedRoot(expected: Kind, actual: Kind)
    /// 输入不是可转换的 JSON 值，例如 Date、自定义类或 nil。
    case unsupportedValue(typeName: String)
    /// LYScalar 无法按白名单规则把来源值转换为目标类型。
    case incompatibleScalar(target: String, source: Kind)
}

extension LYConversionError.Kind {
    /// 判断 Foundation JSON 对象的种类；只看顶层，不遍历子节点。
    init(foundation value: Any) {
        switch value {
        case is NSNull: self = .null
        case let number as NSNumber: self = lyIsBoolean(number) ? .bool : .number
        case is String: self = .string
        case is [String: Any]: self = .object
        case is [Any]: self = .array
        default: self = .other
        }
    }
}

/// 区分 NSNumber 中的布尔值与数字；Swift Bool 桥接后同样是 CFBoolean。
func lyIsBoolean(_ number: NSNumber) -> Bool {
    CFGetTypeID(number) == CFBooleanGetTypeID()
}
