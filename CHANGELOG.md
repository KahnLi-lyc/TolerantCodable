# Changelog

## 0.2.0 (Unreleased)

### Added

- `LYJSONValue`：Sendable、Hashable、Codable 的 JSON 枚举，用来承载结构不固定的字段；支持字面量、精确访问器、`[path:]` 路径下标、与 Foundation 对象互转、`decode(_:)` 解码为模型。
- `@LYLossyDictionary`：丢弃坏键和坏值；缺失、null 或非对象时回退为空字典，键按 JSON 原文转换。
- `@LYLossyOptional`：类型不符时为 nil 并记录诊断；编码时 nil 省略该键。
- `LYDefaultString`、`LYDefaultInt`、`LYDefaultEmptyArray<E>` 等 `LYDefault` 简写。
- 转换工具：`Decodable.decode(fromAny:)`，`Encodable.jsonDictionary()`、`jsonArray()`、`jsonValue()`、`converted(to:)`；`LYJSONSerialization.parseObject`、`parseArray`、`data(fromAny:)`；`[String: Any]`、`[Any]`、`String`、`Data` 的 `ly` 前缀扩展；`Data.lyPrettyJSONString()`。
- `LYScalar`：与 `@LYDefault` 白名单一致的宽松标量转换，失败抛出 `LYConversionError`。
- `LYConversionError`：转换工具的受控错误，只含类型名和 JSON 种类。
- `LYJSONCoder.decodeWithDiagnostics`、`decodeExpectingNoDiagnostics` 与 `LYUnexpectedDiagnosticsError`，用于就地处理诊断和契约测试。
- `LYCodingConfiguration.snakeCase` 预设。
- `Examples/`：iOS SwiftUI 示例工程（XcodeGen）及 UI 冒烟测试。

### Changed

- 按路径解码支持数组下标，例如 `"data.items.0.name"`；纯数字段遇到对象时仍按键处理，越界时抛出带完整路径的 `DecodingError.valueNotFound`。
- 错误码 `LYConversionError.Kind` 的描述为简短名称（如 `null`）。

### Performance

- 与 0.1.0 同时段对比（`CodableBenchmark` run4，macOS，release，30 轮中位数）：按路径解码 `data.items` 为 2,531 µs（0.1.0 为 2,615 µs，均约为原生的 2.2 倍），干净数据 100 条为 2,476 µs（0.1.0 为 2,542 µs），没有性能退化。

## 0.1.0 (2026-11-04)

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
