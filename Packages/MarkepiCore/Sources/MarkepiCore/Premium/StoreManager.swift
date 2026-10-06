import Foundation
import Observation
import StoreKit
import os.log

/// The single source of truth for StoreKit 2 — product loading, purchasing,
/// restoring, and entitlement tracking for "Markepi Pro".
///
/// Created once at app launch (see `WatermarkApp`) and injected into the SwiftUI
/// environment so the paywall can drive purchases and read live prices. On every
/// entitlement change it mirrors the result into ``PremiumStatusStore`` so the
/// Share Extension and the export gate see the same premium status without
/// running their own StoreKit listener.
///
/// Every product grants the same entitlement, so `isPremium` is simply
/// "owns any product in the catalog".
@MainActor
@Observable
public final class StoreManager {

    /// Loaded products, ordered to match ``PremiumProduct/allCases``
    /// (lifetime, lifetime sale, monthly, annual).
    public private(set) var products: [Product] = []

    /// Identifiers the user currently owns (active, non-revoked entitlements).
    public private(set) var purchasedProductIDs: Set<String> = []

    /// True while the initial product fetch is in flight.
    public private(set) var isLoadingProducts = false

    /// True if the last product fetch failed (offline, misconfigured IDs).
    public private(set) var loadFailed = false

    /// Whether the user holds any premium entitlement.
    public var isPremium: Bool {
        #if DEBUG
        if debugForcePremium { return true }
        #endif
        return !purchasedProductIDs.isEmpty
    }

    #if DEBUG
    /// Debug-only toggle that force-grants premium regardless of real
    /// entitlements (see ``DebugPremium``). Observable, so flipping it in
    /// Settings immediately refreshes the paywall and anything reading
    /// ``isPremium``; its `didSet` mirrors the value into the App Group so the
    /// export gate and Share Extension honor it too. Absent in Release builds.
    public var debugForcePremium: Bool = DebugPremium.isForced {
        didSet {
            DebugPremium.isForced = debugForcePremium
            // Keep the shared cache coherent for readers that snapshot it.
            statusStore.set(isPremium)
        }
    }

    /// Debug-only: show a sale built from the normal lifetime price (40% of
    /// it, ending in .99), so the sale UI can be checked in any storefront —
    /// or with no products loaded at all — without App Store Connect. Absent
    /// in Release builds.
    public var debugSimulateSale: Bool = DebugPremium.simulatesSale {
        didSet { DebugPremium.simulatesSale = debugSimulateSale }
    }
    #endif

    private let statusStore: PremiumStatusStore

    public init(statusStore: PremiumStatusStore = .shared) {
        self.statusStore = statusStore

        // Listen for transactions from every source: renewals, Ask-to-Buy
        // approvals, Family Sharing, and purchases made on other devices.
        Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }

        // Prime the catalog and entitlement snapshot at launch.
        Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshEntitlements()
        }
    }

    // MARK: - Lookup

    /// The loaded `Product` backing a catalog entry, or `nil` if it failed to
    /// load (offline / not yet configured in App Store Connect).
    public func product(for premium: PremiumProduct) -> Product? {
        products.first { $0.id == premium.rawValue }
    }

    // MARK: - Lifetime sale

    /// What the lifetime plan shows and buys. Never on sale for a Pro user:
    /// there is nothing left to sell them.
    public var lifetimeOffer: LifetimeOffer? {
        let normal = product(for: .lifetime).map(Self.price)
        var sale = product(for: .lifetimeSale).map(Self.price)
        #if DEBUG
        var normalPrice = normal
        if debugSimulateSale {
            let base = product(for: .lifetime)
            // MARKEPI_SALE_CURRENCY=VND MARKEPI_SALE_PRICE=129000 previews long currencies.
            let env = ProcessInfo.processInfo.environment
            let code = env["MARKEPI_SALE_CURRENCY"]
            let style = code.map { Decimal.FormatStyle.Currency(code: $0) }
                ?? base?.priceFormatStyle ?? Decimal.FormatStyle.Currency(code: "USD")
            let full = env["MARKEPI_SALE_PRICE"].flatMap { Decimal(string: $0) }
                ?? base?.price ?? Decimal(string: "4.99")!
            // 40% of the price, up to the next whole unit, minus 0.01: $4.99 → $1.99.
            var cut = full * Decimal(string: "0.4")!, up = Decimal()
            NSDecimalRound(&up, &cut, 0, .up)
            let price = up - Decimal(string: "0.01")!
            if normal == nil || code != nil {
                normalPrice = .init(id: PremiumProduct.lifetime.rawValue, price: full,
                                    displayPrice: full.formatted(style))
            }
            sale = .init(id: normalPrice!.id, price: price, displayPrice: price.formatted(style))
        }
        #else
        let normalPrice = normal
        #endif
        guard let offer = LifetimeOffer.make(normal: normalPrice, sale: sale) else { return nil }
        guard isPremium, offer.isOnSale else { return offer }
        return LifetimeOffer.make(normal: normalPrice, sale: nil)
    }

    private static func price(_ p: Product) -> LifetimeOffer.Price {
        .init(id: p.id, price: p.price, displayPrice: p.displayPrice)
    }

    /// The loaded product a lifetime purchase should buy (sale or normal).
    public var lifetimePurchaseProduct: Product? {
        guard let id = lifetimeOffer?.purchaseID else { return nil }
        return products.first { $0.id == id }
    }

    // MARK: - Product loading

    public func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: PremiumProduct.allIdentifiers)
            // Preserve catalog order regardless of the order the API returns.
            products = PremiumProduct.allCases.compactMap { entry in
                loaded.first { $0.id == entry.rawValue }
            }
            loadFailed = false
        } catch {
            loadFailed = true
            #if DEBUG
            os_log(.error, log: .markepi, "[StoreManager] Failed to load products: %{public}@",
                   error.localizedDescription)
            #endif
        }
    }

    // MARK: - Purchase

    /// The outcome of a purchase attempt, in a form safe to hand back to the UI.
    public enum PurchaseOutcome: Sendable, Equatable {
        /// Purchase completed and the entitlement is now active.
        case success
        /// The user dismissed the payment sheet.
        case cancelled
        /// Awaiting external action (Ask-to-Buy, SCA). Delivered later via
        /// `Transaction.updates`.
        case pending
        /// Purchase failed; the string is a user-presentable message.
        case failed(String)
    }

    @discardableResult
    public func purchase(_ premium: PremiumProduct) async -> PurchaseOutcome {
        guard let product = product(for: premium) else {
            return .failed("This item isn't available right now. Please try again later.")
        }
        return await purchase(product)
    }

    @discardableResult
    public func purchase(_ product: Product) async -> PurchaseOutcome {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("We couldn't verify that purchase. No charge was made.")
                }
                await refreshEntitlements()
                await transaction.finish()
                return .success
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("Something went wrong. Please try again.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Restore

    /// Restores previous purchases. Required by App Review for any app selling
    /// non-consumables or subscriptions.
    public func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    // MARK: - Entitlements

    /// Recomputes owned products from `Transaction.currentEntitlements` and
    /// mirrors the premium flag into the App Group cache.
    public func refreshEntitlements() async {
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil else { continue }
            owned.insert(transaction.productID)
        }
        purchasedProductIDs = owned
        statusStore.set(!owned.isEmpty)
    }

    // MARK: - Transaction listener

    private func handle(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            await transaction.finish()
            await refreshEntitlements()
        case .unverified(let transaction, _):
            // Clear the unverified transaction from the queue without granting.
            await transaction.finish()
        }
    }
}
