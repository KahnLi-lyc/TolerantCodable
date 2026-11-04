# Changelog

## 0.1.0 (Unreleased)

首个版本，移植自 Club Circle iOS 客户端中经生产验证的 Coding 工具。

### Added

- `@LYDefault<Provider>`：先直接解码，再做白名单内的标量转换，最后回退到 `Provider.defaultValue`；内置 String、Int、Int64、Double、Float、Decimal、Bool、空数组、空字典等默认值。
- `@LYLossyArray`：逐个元素解码并丢弃坏元素；缺失、null 或非数组时回退为空数组。
- `@LYFlexibleDate`：兼容秒/毫秒时间戳、纯日期、带或不带时区的 ISO8601 与空格分隔格式，非法值回退 Unix epoch。
- `LYUnknownCaseDecodable`：无法识别的枚举原始值解码为 `unknownCase`，提供 `knownCases` 与 `isKnown`。
- `LYJSONCoder`：每次调用使用独立的 decoder/encoder，通过 `onDiagnostic` 输出脱敏的结构化诊断；支持 `decode(_:from:atPath:)` 单次解析按路径解码。
- `LYDiagnosticSink`、`LYDiagnosticCollector`：可注入原生 `JSONDecoder` 的统一诊断通道。
- `LYJSONSerialization`：Foundation JSON 对象与 Data/String 的安全互转。
- `Decodable.decode(fromJSON:)`、`decode(fromJSONObject:)`，`Encodable.jsonData()`、`jsonString(prettyPrinted:)`、`jsonObject()`。

### Performance

- 包装器与数组在类型正确时走快速路径，跳过 `superDecoder`，干净数据约为原生 JSONDecoder 的 2 倍耗时。
