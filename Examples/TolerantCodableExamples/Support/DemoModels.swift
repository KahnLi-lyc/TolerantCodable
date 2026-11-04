import Foundation
import TolerantCodable

/// 商品状态：服务端新增的状态落到 unknown，而不是让整个列表解码失败。
enum ProductStatus: String, Codable, CaseIterable, Sendable, LYUnknownCaseDecodable {
    case active, draft, soldOut = "sold_out", unknown

    static var unknownCase: Self {
        .unknown
    }
}

/// 覆盖全部包装器的商品模型；未包装的 id 仍然严格。
struct Product: Codable, Sendable, Identifiable {
    let id: String
    @LYDefaultString var title: String
    @LYDefaultDouble var price: Double
    @LYDefaultFalse var onSale: Bool
    @LYLossyArray var tags: [String]
    @LYLossyDictionary var stock: [String: Int]
    @LYLossyOptional var rating: Double?
    @LYFlexibleDate var updatedAt: Date
    var status: ProductStatus
}

/// Socket 推送的聊天消息。
struct ChatMessage: Codable, Sendable {
    let id: Int
    @LYDefaultString var text: String
    @LYDefaultInt var senderLevel: Int

    init(id: Int, text: String, senderLevel: Int) {
        self.id = id
        self.text = text
        self.senderLevel = senderLevel
    }
}

/// 业务层实体，用 `converted(to:)` 从 DTO 得到。
struct ChatMessageEntity: Decodable, Sendable {
    let id: Int
    let text: String
}

/// 结构不固定的事件：payload 用 LYJSONValue 承载。
struct LiveEvent: Codable, Sendable {
    let type: String
    let payload: LYJSONValue
}

/// 从 payload 中按需解码出的礼物信息。
struct Gift: Decodable, Sendable {
    let giftId: String
    @LYDefaultInt var count: Int
}
