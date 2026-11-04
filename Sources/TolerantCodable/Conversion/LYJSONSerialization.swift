import Foundation

/// 同步 JSON 对象转换边界；不记录原文，不把裸 Any 跨并发边界传递。
public enum LYJSONSerialization {
    // MARK: - Parsing

    /// 将 JSON 数据解析为 Foundation 对象；默认仅接受对象或数组根节点，错误原样抛出。
    public static func parse(_ data: Data, options: JSONSerialization.ReadingOptions = []) throws -> Any {
        try JSONSerialization.jsonObject(with: data, options: options)
    }

    /// 将 UTF-8 JSON 文本解析为 Foundation 对象；标量根节点需显式传入 fragmentsAllowed。
    public static func parse(_ string: String, options: JSONSerialization.ReadingOptions = []) throws -> Any {
        try parse(Data(string.utf8), options: options)
    }

    /// 解析为 JSON 对象（字典）；根节点不是对象时抛出 `LYConversionError.unexpectedRoot`。
    public static func parseObject(_ data: Data) throws -> [String: Any] {
        let object = try parse(data)
        guard let dictionary = object as? [String: Any] else {
            throw LYConversionError.unexpectedRoot(expected: .object, actual: .init(foundation: object))
        }
        return dictionary
    }

    /// 解析 UTF-8 文本为 JSON 对象（字典）。
    public static func parseObject(_ string: String) throws -> [String: Any] {
        try parseObject(Data(string.utf8))
    }

    /// 解析为 JSON 数组；根节点不是数组时抛出 `LYConversionError.unexpectedRoot`。
    public static func parseArray(_ data: Data) throws -> [Any] {
        let object = try parse(data)
        guard let array = object as? [Any] else {
            throw LYConversionError.unexpectedRoot(expected: .array, actual: .init(foundation: object))
        }
        return array
    }

    /// 解析 UTF-8 文本为 JSON 数组。
    public static func parseArray(_ string: String) throws -> [Any] {
        try parseArray(Data(string.utf8))
    }

    // MARK: - Normalization

    /// 把形态不确定的 JSON 载荷（Socket、推送、桥接回调的参数）统一为 Data：
    /// - `Data` 原样返回，`String` / `NSString` 转为 UTF-8；文本不做二次语法校验，由下游解码负责。
    /// - `[String: Any]`、`[Any]`（含 NSDictionary / NSArray）先校验再序列化。
    /// - `LYJSONValue` 直接编码。
    /// - nil、NSNull 及其他类型抛出 `LYConversionError.unsupportedValue`。
    public static func data(fromAny value: Any?) throws -> Data {
        guard let value else { throw LYConversionError.unsupportedValue(typeName: "nil") }
        switch value {
        case let data as Data:
            return data
        case let string as String:
            return Data(string.utf8)
        case let json as LYJSONValue:
            return try JSONEncoder().encode(json)
        case is [String: Any], is [Any]:
            return try data(from: value)
        default:
            throw LYConversionError.unsupportedValue(typeName: String(reflecting: type(of: value)))
        }
    }

    // MARK: - Serialization

    /// 将有效 JSON 对象编码为数据；默认只允许对象或数组根节点。
    /// - Throws: 非 JSON 对象、非有限数字或未允许的标量根节点抛出 CocoaError；不执行静默降级。
    public static func data(from object: Any, options: JSONSerialization.WritingOptions = []) throws -> Data {
        // 先检查包裹后的对象，避免向 Foundation 传入非法对象而触发 Objective-C 异常。
        guard JSONSerialization.isValidJSONObject([object]),
              options.contains(.fragmentsAllowed) || JSONSerialization.isValidJSONObject(object)
        else {
            throw CocoaError(.propertyListWriteInvalid)
        }
        return try JSONSerialization.data(withJSONObject: object, options: options)
    }

    /// 将有效 JSON 对象编码为 UTF-8 文本；格式选项与 data(from:options:) 一致。
    public static func string(from object: Any, options: JSONSerialization.WritingOptions = []) throws -> String {
        let encoded = try data(from: object, options: options)
        guard let string = String(data: encoded, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return string
    }
}
