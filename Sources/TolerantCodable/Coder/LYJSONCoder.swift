import Foundation

/// 编解码策略工厂。每次调用必须返回独立实例，避免并发共享可变 JSONDecoder/JSONEncoder。
public struct LYCodingConfiguration: Sendable {
    /// 创建一次解码专用的 decoder。
    public var makeDecoder: @Sendable () -> JSONDecoder
    /// 创建一次编码专用的 encoder。
    public var makeEncoder: @Sendable () -> JSONEncoder
    /// 接收结构化诊断；在调用 decode 的线程上、decode 返回或抛错之前执行。
    public var onDiagnostic: @Sendable (LYDecodingDiagnostic) -> Void
    /// 单次解码最多保留的诊断条数。
    public var diagnosticLimit: Int

    /// 默认使用 Foundation 策略和独立实例；诊断回调默认为空。
    public init(
        makeDecoder: @escaping @Sendable () -> JSONDecoder = { JSONDecoder() },
        makeEncoder: @escaping @Sendable () -> JSONEncoder = { JSONEncoder() },
        diagnosticLimit: Int = 50,
        onDiagnostic: @escaping @Sendable (LYDecodingDiagnostic) -> Void = { _ in }
    ) {
        self.makeDecoder = makeDecoder
        self.makeEncoder = makeEncoder
        self.diagnosticLimit = diagnosticLimit
        self.onDiagnostic = onDiagnostic
    }
}

/// 可并发调用的 JSON 编解码入口；只对显式包装的字段启用兼容策略，其余字段保持 Codable 原有的严格语义。
public struct LYJSONCoder: Sendable {
    // MARK: - Properties

    private let configuration: LYCodingConfiguration

    // MARK: - Initialization

    /// 注入每次调用的策略工厂与诊断出口。
    public init(configuration: LYCodingConfiguration = .init()) {
        self.configuration = configuration
    }

    // MARK: - Encoding

    /// 使用本次调用独占的 encoder 编码；错误原样抛出。
    public func encode(_ value: some Encodable) throws -> Data {
        try configuration.makeEncoder().encode(value)
    }

    /// 在配置的 encoder 上追加输出格式后编码，例如 `.prettyPrinted`。
    public func encode(_ value: some Encodable, adding formatting: JSONEncoder.OutputFormatting) throws -> Data {
        let encoder = configuration.makeEncoder()
        encoder.outputFormatting.formUnion(formatting)
        return try encoder.encode(value)
    }

    /// 输出 UTF-8 JSON 文本；错误原样抛出，不返回空对象。
    public func encodeString(_ value: some Encodable, prettyPrinted: Bool = false) throws -> String {
        let data = try prettyPrinted ? encode(value, adding: [.prettyPrinted, .sortedKeys]) : encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Decoding

    /// 解码并汇总兼容诊断；语法错误、根结构不符及未包装字段错误仍然抛出。
    public func decode<T: Decodable>(_ type: T.Type, from data: Data, context: LYCodingContext = .init()) throws -> T {
        try run(type, context: context) { decoder in try decoder.decode(type, from: data) }
    }

    /// 解码 UTF-8 JSON 文本；复用 Data 入口的校验与诊断。
    public func decode<T: Decodable>(_ type: T.Type, from string: String, context: LYCodingContext = .init()) throws -> T {
        try decode(type, from: Data(string.utf8), context: context)
    }

    /// 只解码 `path` 指向的子节点，例如 `"data.items"`；单次解析，不经过 Any 中转。
    /// 路径只支持对象键；某层缺失或不是对象时抛出带路径的 DecodingError。
    public func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        atPath path: String,
        context: LYCodingContext = .init()
    ) throws -> T {
        let keys = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !path.isEmpty else { return try decode(type, from: data, context: context) }
        guard !keys.contains(where: \.isEmpty) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid key path"))
        }
        return try run(type, context: context) { decoder in
            decoder.userInfo[.lyDecodingPath] = keys
            return try decoder.decode(LYPathDecodable<T>.self, from: data).value
        }
    }

    private func run<T>(_ type: T.Type, context: LYCodingContext, _ body: (JSONDecoder) throws -> T) throws -> T {
        let collector = LYDiagnosticCollector(model: String(reflecting: type), context: context, limit: configuration.diagnosticLimit)
        let decoder = configuration.makeDecoder()
        decoder.userInfo[.lyDiagnostics] = collector
        defer { collector.diagnostics.forEach(configuration.onDiagnostic) }
        do {
            return try body(decoder)
        } catch {
            collector.recordFailure(error, target: String(reflecting: type))
            throw error
        }
    }
}
