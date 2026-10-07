import Foundation
import Testing
@testable import MarkepiCore

@Suite("Lifetime sale offer")
struct LifetimeOfferTests {
    private let normal = LifetimeOffer.Price(id: PremiumProduct.lifetime.rawValue, price: 4.99, displayPrice: "$4.99")
    private func sale(_ p: Decimal, _ s: String) -> LifetimeOffer.Price {
        .init(id: PremiumProduct.lifetimeSale.rawValue, price: p, displayPrice: s)
    }

    @Test("Sale price lower: on sale, buys the sale product, strikes the normal price")
    func lower() throws {
        let o = try #require(LifetimeOffer.make(normal: normal, sale: sale(1.99, "$1.99")))
        #expect(o.isOnSale)
        #expect(o.purchaseID == PremiumProduct.lifetimeSale.rawValue)
        #expect(o.displayPrice == "$1.99")
        #expect(o.originalDisplayPrice == "$4.99")
    }

    @Test("Equal or higher sale price: no sale, normal product")
    func equalOrHigher() throws {
        for s in [sale(4.99, "$4.99"), sale(6.99, "$6.99")] {
            let o = try #require(LifetimeOffer.make(normal: normal, sale: s))
            #expect(!o.isOnSale)
            #expect(o.purchaseID == PremiumProduct.lifetime.rawValue)
            #expect(o.displayPrice == "$4.99")
        }
    }

    @Test("Only one product loaded: unstruck; none: nil")
    func missing() throws {
        let n = try #require(LifetimeOffer.make(normal: normal, sale: nil))
        #expect(!n.isOnSale && n.purchaseID == PremiumProduct.lifetime.rawValue)
        let s = try #require(LifetimeOffer.make(normal: nil, sale: sale(1.99, "$1.99")))
        #expect(!s.isOnSale && s.purchaseID == PremiumProduct.lifetimeSale.rawValue)
        #expect(LifetimeOffer.make(normal: nil, sale: nil) == nil)
    }

    @Test("Catalog: sale product is loaded and is not a subscription")
    func catalog() {
        #expect(PremiumProduct.allIdentifiers.contains("markepi.pro.lifetime.sale"))
        #expect(!PremiumProduct.lifetimeSale.isSubscription)
        #expect(PremiumProduct.annual.isSubscription && PremiumProduct.monthly.isSubscription)
    }
}
