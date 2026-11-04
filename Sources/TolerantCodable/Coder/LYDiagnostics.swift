import Foundation
import os

/// 单次解码的调用上下文；只传入不含凭据的接口标识和请求 ID。
public struct LYCodingContext: Sendable, Equatable {
    /// 调用方提供的接口标识，不应包含 query 或用户输入。
    public var endpoint: String?
    /// 用于关联请求的非敏感标识。
    public var requestID: String?

    /// 创建可选的解码上下文。
    public init(endpoint: String? = nil, requestID: String? = nil) {
        self.endpoint = endpoint
        self.requestID = requestID
    }
}

/// 不携带原始字段值及底层错误描述的结构化解码记录。
public struct LYDecodingDiagnostic: Sendable, Equatable {
    /// 发生的兼容处理或严格解码失败。
    public enum Kind: String, Sendable {
        /// 类型转换成功。
        case conversion
        /// 使用声明的默认值或枚举兜底。
        case fallback
        /// 丢弃一个无法解码的数组元素。
        case discard
        /// 整次解码失败。
        case failure
        /// 超出记录上限而省略的条数，数量写在 reason 中。
        case suppressed
    }

    /// 诊断事件类型。
    public let kind: Kind
    /// 顶层目标模型类型。
    public let model: String
    /// 从根到当前字段的 CodingKey 路径。
    public let codingPath: [String]
    /// 路径中最近的数组索引。
    public let arrayIndex: Int?
    /// 当前字段期望的类型。
    public let targetType: String
    /// 受控原因码；不包含原始值或 debugDescription。
    public let reason: String
    /// 当前解码的接口和请求标识。
    public let context: LYCodingContext
}

/// 接收兼容处理记录；由 decoder.userInfo[.lyDiagnostics] 注入，可能在调用 decode 的任意线程同步执行。
public protocol LYDiagnosticSink: Sendable {
    /// 记录一次兼容处理；不会收到原始值。
    func record(_ kind: LYDecodingDiagnostic.Kind, codingPath: [any CodingKey], targetType: String, reason: String)
}

public extension CodingUserInfoKey {
    /// 注入 LYDiagnosticSink 的固定 key；未注入时所有兼容处理保持静默。
    static var lyDiagnostics: CodingUserInfoKey {
        // CodingUserInfoKey 仅拒绝空字符串；此常量始终有效。
        guard let key = CodingUserInfoKey(rawValue: "TolerantCodable.diagnostics") else {
            preconditionFailure("Invalid diagnostics userInfo key")
        }
        return key
    }
}

/// 锁保护的有界诊断收集器；LYJSONCoder 每次 decode 独占一个实例，也可手动注入原生 JSONDecoder。
public final class LYDiagnosticCollector: LYDiagnosticSink {
    private struct State {
        var records: [LYDecodingDiagnostic] = []
        var suppressed = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let model: String
    private let context: LYCodingContext
    private let limit: Int

    /// limit 限制保留条数；超出后最终失败仍替换最后一条，其余只计数。
    public init(model: String = "", context: LYCodingContext = .init(), limit: Int = 50) {
        self.model = model
        self.context = context
        self.limit = max(1, limit)
    }

    /// 已记录的诊断；若有省略，末尾附加一条 suppressed。
    public var diagnostics: [LYDecodingDiagnostic] {
        state.withLock { state in
            guard state.suppressed > 0 else { return state.records }
            return state.records + [LYDecodingDiagnostic(
                kind: .suppressed, model: model, codingPath: [], arrayIndex: nil, targetType: model,
                reason: String(state.suppressed), context: context
            )]
        }
    }

    public func record(_ kind: LYDecodingDiagnostic.Kind, codingPath: [any CodingKey], targetType: String, reason: String) {
        let diagnostic = LYDecodingDiagnostic(
            kind: kind,
            model: model,
            codingPath: codingPath.map(\.stringValue),
            arrayIndex: codingPath.reversed().compactMap(\.intValue).first,
            targetType: targetType,
            reason: reason,
            context: context
        )
        state.withLock {
            if $0.records.count < limit {
                $0.records.append(diagnostic)
            } else {
                // 最终失败保留真实字段与原因，避免调用方只看到省略数量。
                if kind == .failure {
                    $0.records.removeLast()
                    $0.records.append(diagnostic)
                }
                $0.suppressed += 1
            }
        }
    }

    /// 把 DecodingError 映射为受控原因码，不保留 debugDescription。
    func recordFailure(_ error: any Error, target: String) {
        var path: [any CodingKey] = []
        var expected = target
        let reason: String
        switch error {
        case let DecodingError.keyNotFound(key, context):
            path = context.codingPath + [key]
            reason = "missing_required_key"
        case let DecodingError.typeMismatch(type, context):
            expected = String(reflecting: type)
            path = context.codingPath
            reason = "type_mismatch"
        case let DecodingError.valueNotFound(type, context):
            expected = String(reflecting: type)
            path = context.codingPath
            reason = "required_value_missing"
        case let DecodingError.dataCorrupted(context):
            path = context.codingPath
            reason = "invalid_data"
        default:
            reason = "decoding_failed"
        }
        record(.failure, codingPath: path, targetType: expected, reason: reason)
    }
}

extension Decoder {
    /// 未注入 sink 时静默；不读取或转发原始值。
    func lyRecord(_ kind: LYDecodingDiagnostic.Kind, target: Any.Type, reason: String) {
        (userInfo[.lyDiagnostics] as? any LYDiagnosticSink)?.record(
            kind, codingPath: codingPath, targetType: String(reflecting: target), reason: reason
        )
    }
}
