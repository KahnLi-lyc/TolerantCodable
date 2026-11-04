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
