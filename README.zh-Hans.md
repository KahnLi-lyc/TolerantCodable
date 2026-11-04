# TolerantCodable

[English](README.md)

**默认严格、显式容错、可诊断**的 Swift 6 Codable 扩展。

- 未标注的字段保持 Codable 原有的严格语义，服务端契约漂移不会被悄悄掩盖。
- 只有你显式包装的字段才会兼容：字符串数字、null、缺失字段、坏数组元素、多种日期格式、新增的枚举值。
- 每一次兼容处理都会留下脱敏的结构化诊断，记录类型、字段路径和原因码，不包含原始值。
- 直接基于系统 `JSONDecoder`，零依赖，严格并发下零警告。

## 安装

```swift
.package(url: "https://github.com/KahnLi-lyc/TolerantCodable.git", from: "0.1.0")
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
| `LYUnknownCaseDecodable` | 新增的枚举原始值 | `unknownCase` | 原始值类型错误、null、缺失 |

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

## 转换工具

| 方法 | 说明 |
|---|---|
| `T.decode(fromJSON: Data/String, atPath:)` | 解码；`atPath` 例如 `"data.items"`，单次解析，不经过 Any 中转 |
| `T.decode(fromJSONObject: [String: Any] / [Any])` | 先校验对象合法，再解码 |
| `value.jsonData()` / `jsonString(prettyPrinted:)` / `jsonObject()` | 编码为 Data、文本或 Foundation 对象 |
| `LYJSONSerialization.parse/data/string` | 安全的 JSONSerialization 封装，非法对象抛错而不是触发 ObjC 异常 |

所有方法失败时都抛出错误，不返回 nil。

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

键映射（多个候选 key）、`Any` / `[String: Any]` 属性、类继承、值转换器、按路径解码数组下标。

## License

MIT
