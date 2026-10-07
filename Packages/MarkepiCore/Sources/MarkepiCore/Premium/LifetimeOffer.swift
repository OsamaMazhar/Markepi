import Foundation

/// What the lifetime plan shows and sells, decided from the two lifetime
/// products' store prices.
///
/// A sale is on exactly when both products loaded and the sale product is
/// strictly cheaper than the normal one. Both prices come from the same
/// storefront, so comparing the `Decimal`s is exact. Equal, higher or missing
/// means no sale, so the app can never show "SALE" at a worse price.
public struct LifetimeOffer: Equatable, Sendable {
    /// One lifetime product's store price.
    public struct Price: Equatable, Sendable {
        public let id: String
        public let price: Decimal
        public let displayPrice: String

        public init(id: String, price: Decimal, displayPrice: String) {
            self.id = id
            self.price = price
            self.displayPrice = displayPrice
        }
    }

    /// The product a lifetime purchase buys.
    public let purchaseID: String
    /// The price to quote: the sale price while on sale, otherwise the normal one.
    public let displayPrice: String
    /// The normal price, struck through. Non-nil only while on sale.
    public let originalDisplayPrice: String?

    public var isOnSale: Bool { originalDisplayPrice != nil }

    public init(purchaseID: String, displayPrice: String, originalDisplayPrice: String? = nil) {
        self.purchaseID = purchaseID
        self.displayPrice = displayPrice
        self.originalDisplayPrice = originalDisplayPrice
    }

    /// `nil` when neither product loaded (the paywall then shows its fallback price).
    public static func make(normal: Price?, sale: Price?) -> LifetimeOffer? {
        switch (normal, sale) {
        case let (normal?, sale?) where sale.price < normal.price:
            return LifetimeOffer(purchaseID: sale.id, displayPrice: sale.displayPrice,
                                 originalDisplayPrice: normal.displayPrice)
        case let (normal?, _):
            return LifetimeOffer(purchaseID: normal.id, displayPrice: normal.displayPrice)
        case let (nil, sale?):
            return LifetimeOffer(purchaseID: sale.id, displayPrice: sale.displayPrice)
        case (nil, nil):
            return nil
        }
    }
}
