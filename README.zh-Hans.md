# TolerantCodable

[English](README.md)

**默认严格、显式容错、可诊断**的 Swift 6 Codable 扩展。

- 未标注的字段保持 Codable 原有的严格语义，服务端契约漂移不会被悄悄掩盖。
- 只有你显式包装的字段才会兼容：字符串数字、null、缺失字段、坏数组元素、多种日期格式、新增的枚举值。
- 每一次兼容处理都会留下脱敏的结构化诊断，记录类型、字段路径和原因码，不包含原始值。
- 直接基于系统 `JSONDecoder`，零依赖，严格并发下零警告。

## 安装

```swift
.package(url: "https://github.com/KahnLi-lyc/TolerantCodable.git", from: "0.2.0")
```

系统要求：iOS 16 / macOS 13 / tvOS 16 / watchOS 9，Swift 6。

## 快速上手

```swift
import TolerantCodable

enum Role: String, Codable, LYUnknownCaseDecodable {
    case owner, member
    case unknown
    static var unknownCase: Self { .unknown }
}

struct Member: Codable {
    let id: String                                        // 严格：缺失或类型错误直接抛出
    @LYDefault<LYDefaults.Int> var age: Int               // "30" → 30，null/缺失 → 0
    @LYDefault<LYDefaults.False> var verified: Bool       // 1 / "true" → true
    @LYLossyArray var tags: [String]                      // 丢弃坏元素
    @LYFlexibleDate var joinedAt: Date                    // 时间戳或 ISO8601
    var role: Role                                        // 新取值 → .unknown
}

let members = try [Member].decode(fromJSON: data, atPath: "data.items")
```

## 包装器语义

| 类型 | 能兼容的输入 | 回退 | 仍然严格的情况 |
|---|---|---|---|
| `@LYDefault<P>` | 白名单标量转换：字符串与数字、Bool 与 0/1/"true"；整数经 Decimal 转换，保留 Int64 精度；拒绝 NaN、inf、十六进制 | `P.defaultValue` | 无（用于可安全降级的字段） |
| `@LYLossyArray` | 逐个元素解码 | 坏元素丢弃；缺失、null、非数组时为 `[]` | 元素自身仍按其 Decodable 契约解码 |
| `@LYFlexibleDate` | 秒或毫秒时间戳、数字字符串、`yyyy-MM-dd`、`T` 或空格分隔、带或不带时区、任意位小数秒 | Unix epoch | 2 月 30 日、24 时、非法时区偏移一律回退 |
| `@LYLossyDictionary` | 逐条解码，键按 JSON 原文转换为 `Key`（`LosslessStringConvertible`） | 坏键、坏值丢弃；缺失、null、非对象时为 `[:]` | 值自身仍按其 Decodable 契约解码 |
| `@LYLossyOptional` | 类型不符的值 | `nil`（缺失与 null 本就是 nil，不记诊断） | 无；编码时 nil 省略该键 |
| `LYUnknownCaseDecodable` | 新增的枚举原始值 | `unknownCase` | 原始值类型错误、null、缺失 |

常用组合有简写：`@LYDefaultString`、`@LYDefaultInt`、`@LYDefaultInt64`、`@LYDefaultDouble`、`@LYDefaultFloat`、`@LYDefaultDecimal`、`@LYDefaultFalse`、`@LYDefaultTrue`、`@LYDefaultEmptyArray<E>`、`@LYDefaultEmptyDictionary<K, V>`。

自定义默认值：

```swift
enum Anonymous: LYDefaultValueProvider { static var defaultValue: String { "anonymous" } }
@LYDefault<Anonymous> var nickname: String
```

属性声明处写的初始值（如 `= 5`）不参与解码；回退值始终来自 Provider。

## 未知枚举

- 无法识别的值解码为 `unknownCase`，**不要把它映射成任何真实 case**：按最小权限处理，显示通用文案。
- `knownCases` 排除兜底值，用于选择器、订阅和契约比对。
- `unknownCase` 只用于解码，不要作为请求参数发送。

## 诊断

```swift
let coder = LYJSONCoder(configuration: .init(onDiagnostic: { diagnostic in
    print(diagnostic.kind, diagnostic.codingPath, diagnostic.reason)   // 不含原始值
}))
let page = try coder.decode(Page.self, from: data, context: .init(endpoint: "/members", requestID: requestID))
```

- `kind` 取值：`conversion`、`fallback`、`discard`、`failure`、`suppressed`。单次解码默认最多保留 50 条，最终失败一定保留。
- 使用原生 `JSONDecoder` 时，可以手动注入：`decoder.userInfo[.lyDiagnostics] = LYDiagnosticCollector()`；不注入则保持静默。
- `decodeWithDiagnostics` 在返回值的同时返回本次诊断，适合在调用处直接上报或展示。

### 严格契约测试

线上容错，测试里从严：在单元测试或 CI 中用接口 fixture 调用 `decodeExpectingNoDiagnostics`，只要发生任何兼容处理就抛出 `LYUnexpectedDiagnosticsError`，第一时间发现后端字段类型变化、新增枚举值或缺失字段。

```swift
func testMemberListContract() throws {
    _ = try LYJSONCoder().decodeExpectingNoDiagnostics([Member].self, from: fixture("members"), atPath: "data.items")
}
```

### 配置预设

`LYCodingConfiguration.snakeCase` 让 decoder 使用 `.convertFromSnakeCase`、encoder 使用 `.convertToSnakeCase`。按路径解码时，路径段匹配的是转换后的驼峰键（`"userInfo"` 而不是 `"user_info"`）。

## 转换工具

所有方法失败时都抛出错误，不返回 nil；错误只包含类型名和 JSON 种类，不包含原始值。

### 模型 ⇄ JSON

| 方法 | 说明 |
|---|---|
| `T.decode(fromJSON: Data/String, atPath:)` | 解码；`atPath` 例如 `"data.items"`、`"data.items.0.name"`，单次解析，不经过 Any 中转 |
| `T.decode(fromJSONObject: [String: Any] / [Any])` | 先校验对象合法，再解码 |
| `T.decode(fromAny: Any?)` | 形态不确定的载荷（Socket、推送、桥接回调）：Data / String / 字典 / 数组 / LYJSONValue |
| `value.jsonData()` / `jsonString(prettyPrinted:)` / `jsonObject()` | 编码为 Data、文本或 Foundation 对象 |
| `value.jsonDictionary()` / `jsonArray()` / `jsonValue()` | 编码为 `[String: Any]`、`[Any]` 或 `LYJSONValue`；顶层种类不符时抛错 |
| `value.converted(to: Entity.self)` | 模型之间互转（DTO → Entity），诊断照常收集 |

```swift
// 以前：extractJSONData(from:) 返回 nil，失败原因全部丢失
socket.on("message") { args, _ in
    do {
        let message = try ChatMessage.decode(fromAny: args.first)
    } catch {
        report(error)   // LYConversionError.unsupportedValue / DecodingError ……
    }
}
```

### Foundation JSON

| 方法 | 说明 |
|---|---|
| `dict.lyJSONString()` / `lyJSONData()`，`array.lyJSONString()` / `lyJSONData()` | `[String: Any]`、`[Any]` 校验后序列化；替代手写的 `dictionaryToJson` |
| `string.lyJSONObject()` / `lyJSONDictionary()` / `lyJSONArray()`，Data 同名方法 | 解析并检查根节点种类 |
| `data.lyPrettyJSONString()` | 重新排版为缩进、排序键的文本，便于日志与调试 |
| `LYJSONSerialization.parse/parseObject/parseArray/data/string/data(fromAny:)` | 安全的 JSONSerialization 封装，非法对象抛错而不是触发 ObjC 异常 |

### 宽松标量 `LYScalar`

`LYScalar.int/int64/double/float/decimal/bool/string(from: Any?)` 把 Foundation 值或 `LYJSONValue` 按与 `@LYDefault` 完全相同的白名单规则转换，例如 `"12"` → 12、`3.7` → 3、`"TRUE"` → true；`"0x10"`、`"nan"`、超出范围的值抛出 `LYConversionError.incompatibleScalar`。

## LYJSONValue

结构不固定的字段用 `LYJSONValue` 承载，替代 `Any` / `[String: Any]`。它是 `Sendable`、`Hashable`、`Codable` 的枚举，可以安全地跨并发边界传递。

```swift
struct LiveEvent: Codable {
    let type: String
    let payload: LYJSONValue          // 严格：只要是合法 JSON 即可
}

let event = try LiveEvent.decode(fromJSON: data)
event.payload[path: "sender.name"]                // .string("Kahn")
event.payload[path: "combo.2"]?.int64Value        // 3
try LYScalar.int(from: event.payload["count"])    // "3" → 3
let gift = try event.payload.decode(Gift.self)    // 再按需解码为模型
```

- 解码顺序为 null → Bool → Int64 → Double → String → 数组 → 对象，`true` 与 `1` 不会混淆；超出 Int64 的整数以 `.double` 保存。
- `LYJSONValue(any:)` 与 `foundationObject` 和 Foundation 对象互转，NSNumber 会正确区分 Bool 与数字。
- 精确访问器（`stringValue`、`int64Value` 等）类型不符时返回 nil；需要宽松转换时使用 `LYScalar`。

## 示例工程

`Examples/TolerantCodableExamples.xcodeproj` 是一个 iOS 16 SwiftUI 应用，逐页演示包装器（干净 / 脏数据对比与诊断）、未知枚举、按路径解码、严格契约、Socket 载荷互转和 LYJSONValue。工程由 XcodeGen 的 `Examples/project.yml` 生成，本地依赖仓库根目录的包。

## 与 SmartCodable、BetterCodable 的差异

| | TolerantCodable | SmartCodable | BetterCodable |
|---|---|---|---|
| 介入方式 | 显式包装字段 | 自研 Decoder，默认对所有字段容错 | 显式包装字段 |
| 解码器 | 系统 JSONDecoder | JSONSerialization 加 JSONValue 树，再由自研的 Decoder 遍历 | 系统 JSONDecoder |
| 未知枚举 | `unknownCase` | 回退到声明的初始值，即一个真实 case | 需自行处理 |
| 失败结果 | 抛出 DecodingError，附诊断 | 返回 nil | 抛出 DecodingError |
| 诊断 | 结构化、脱敏 | 日志 | 无 |

## 性能

在 Apple M1 Max、macOS 27、Swift 6.4.2 上，release 构建、30 轮取中位数，数据为 100 条记录、每条 20 个字段。基准工程见 `CodableBenchmark`。

| 场景 | 原生严格 | TolerantCodable | SmartCodable |
|---|---|---|---|
| 干净数据 | 1.20 ms | 2.55 ms（2.1x） | 19.96 ms（16.6x） |
| 脏数据 | 整体失败 | 3.21 ms | 19.97 ms |
| 按路径解码 `data.items` | 1.17 ms（需外包一层模型） | 2.55 ms | 19.96 ms |

只在 macOS 上测量；iOS 16 的系统 JSONDecoder 是旧实现，真机结果可能不同。

## 暂不支持

键映射（多个候选 key）、类继承、值转换器。路径段暂不支持转义，键本身包含 `.` 时无法按路径访问。

## License

MIT
