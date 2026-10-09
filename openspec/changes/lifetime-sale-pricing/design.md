## Context

- **Purchases today:** `MarkepiCore/Premium` has `PremiumProduct` (lifetime, monthly, annual) and `StoreManager`. `StoreManager` loads products, buys them, and treats owning any of them as Pro. The paywall (`App/Views/Premium/PaywallView.swift`) shows one `planCard` per `PremiumPlan`. Each card is an `HStack` holding the radio, the title and subtitle, then the price on the trailing side. The price is a single `Text` that can't wrap well.
- **Where the paywall is shown:** as a sheet on iPhone and as a form sheet on iPad, and full screen as the last onboarding page (`onSkip`).
- **Paywall layout:** sizes use `@ScaledMetric`. The layout already scrolls when it doesn't fit; App Review rejected 1.3 (2) for a hidden CTA.
- **Home crown:** the start-screen crown is `PremiumCrownIcon` in `ContentView.swift`. It is grey with a gold sweep for free users and static gold for Pro.
- **AutoAlign's approach:** a `*_record` product that is never sold holds the reference price. The sold product's price is compared against it, and the SALE text and badges are scattered through `PurchaseView`. Its price rows use `.lineLimit(1)` on fixed `VStack`s, which is where long currencies break.
- **Project file:** classic pbxproj. New App code goes into existing files; new `MarkepiCore` files are fine (SPM).

## Goals / Non-Goals

**Goals:**
- One decision point for "is a sale on, and what do we show and sell?", a pure function that is unit-tested.
- One price-group view whose layout comes from the measured width. No device or orientation checks.
- The paywall and the home crown read the same sale state.

**Non-Goals:**
- **Sales on monthly or annual:** StoreKit has subscription offers for those, which is a different mechanism.
- **Countdown timers or end dates in the UI:** StoreKit doesn't expose when a price schedule ends.
- **A SALE marker on the export comparison sheet:** it opens the same paywall, which shows the sale.
- **Localizing the word "SALE":** the app is English-only today. The tag reads from one string, so it's easy to localize later.

## Decisions

### 1. A real sale product, toggled by its price, with the normal lifetime as the reference

- **The products:**
  - Add `PremiumProduct.lifetimeSale = "markepi.pro.lifetime.sale"`, a non-consumable.
  - `markepi.pro.lifetime` stays the reference and the default purchase.
  - The sale product sits at the normal price when idle. Starting a sale means scheduling a lower price for it in App Store Connect; prices can be scheduled with start and end dates, so the sale ends on its own.
- **Alternatives considered:**
  - **AutoAlign's "record" product (a reference product priced high and never sold):** it needs a fake product that App Review sees and that users could find in purchase history. Here the reference is the real product people already buy.
  - **Lowering the normal lifetime price:** nothing to compare against, so no strikethrough. This is the problem the change fixes.
  - **StoreKit promotional or win-back offers:** these exist only for auto-renewable subscriptions, not non-consumables.
  - **Offer codes:** they need a code entered at redemption, so they can't drive an on-screen sale price.

### 2. `LifetimeOffer`: a pure value computed from the two products

- **The type:**

  ```swift
  public struct LifetimeOffer: Equatable, Sendable {
      public let purchaseID: String            // what "buy lifetime" purchases
      public let displayPrice: String          // price to quote (sale or normal)
      public let originalDisplayPrice: String? // non-nil only while on sale
      public var isOnSale: Bool { originalDisplayPrice != nil }
      static func make(normal: (id: String, price: Decimal, display: String)?,
                       sale: (id: String, price: Decimal, display: String)?) -> LifetimeOffer?
  }
  ```

- **How `make` decides:**
  - The sale is on only if both prices exist and `sale.price < normal.price`. Both prices are `Decimal`s in the same storefront currency, so the comparison is exact.
  - If only the normal product exists, that is the offer.
  - If only the sale product exists, it is used unstruck, as a fallback.
  - If neither exists, it returns `nil` and the static fallback price applies.
- **`StoreManager` exposure:** `StoreManager.lifetimeOffer` is computed from `products`, so it is observable without extra state. It returns no sale when `isPremium`. `PaywallView` and `PremiumCrownIcon` both read it.
- **Tests:** unit tests cover equal, lower, higher, missing-either and missing-both cases on plain values, with no StoreKit needed.

### 3. Purchasing and restore

- **Purchasing:** `PremiumPlan.lifetime` buys `store.lifetimeOffer?.purchaseID`, not a fixed product.
- **Restore:** `PremiumProduct.allIdentifiers` includes the sale ID, so it loads. `isPremium` is already "owns anything in the catalog", so restore, Family Sharing and buying on another device need no change.
- **CTA:** the purchase button uses `lifetimeOffer.displayPrice`.

### 4. One plan-row layout for every plan (`PlanRowContent`)

- **One row view for all three plans:** every card uses `PlanRowContent` (in `PaywallView.swift`):
  - The left side holds the name, the badge and the subtitle. The badge is "Save 75%", or SALE in gold during a sale.
  - The right side holds the price column, vertically centred: the sale price, with the struck normal price directly under it.
- **Why one shared row:** the user's review of the first build found the sale price not lining up with the other plans. A shared row means every price sits in one column. The tag also moved into the badge slot, so it no longer competes with the prices.
- **Fit order:** a `ViewThatFits(in: .horizontal)` over two layouts:
  1. The price column on the right.
  2. Prices under the text. An inner `ViewThatFits` puts the price and struck price on one line, or each on its own line.

  The name and badge also use a `ViewThatFits`: side by side, or the badge under the name.
- **Subtitle width:** the subtitle reports an ideal width of 0 (`.frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity)`). It therefore wraps instead of claiming a full line in the fit test, which would push every price down.
- **No shrinking:** prices are `.fixedSize()`, with no `minimumScaleFactor`. They move to a new line, never truncate.
- **Accessibility sizes:** the same row also fixes the existing mid-word breaks at those sizes ("An nu al").
- **Why `ViewThatFits`, not a `GeometryReader` threshold:** it measures each layout at the real width. That covers currencies, Dynamic Type, iPad and landscape with no device checks or magic numbers.
- **Previews:** previews cover the four currency pairs and the annual row at three widths.
- **Simple, bold paywall (same review):**
  - The close control is a bare bold `xmark`. The toolbar's glass button supplies the circle; `xmark.circle.fill` drew a second circle inside it.
  - The free-tier card becomes one line.
  - The "Go full quality" label is gone.
  - The headline is heavier, plan names are bold, prices are heavy, and the button title is bolder.
  - The selected plan gets a filled check and a 3 pt accent border.

### 5. Home crown: crown + SALE in one capsule

- **Change:** `PremiumCrownIcon` gains `onSale: Bool`, set to `!store.isPremium && store.lifetimeOffer?.isOnSale == true`.
- **While on sale:**
  - The label becomes `HStack { crown, Text("SALE") }`, padded into a capsule. This follows AutoAlign's "in the same capsule, not a word hanging under the button".
  - The crown and text use the gold gradient instead of grey.
  - The existing gold sweep is masked over the whole label, so the sale reads as an event without new motion code.
  - Reduce Motion drops the sweep.
- **Accessibility label:** "Upgrade to Premium, on sale".
- **No sale:** today's view, byte-for-byte.

### 6. DEBUG "Simulate Sale"

- **Toggle:** a DEBUG-only Settings toggle next to "Force Premium". It sets `StoreManager.debugSimulateSale`.
- **What it does:** `lifetimeOffer` then reports a sale built from the normal product. The original is the real `displayPrice`, and the sale price is 40% of it, formatted with `product.priceFormatStyle`. The whole UI can be checked in the Simulator or on device in any storefront with no App Store Connect change.
- **Release builds:** compiled out.
- **StoreKit file:** `Markepi.storekit` gains the sale product at $4.99, so local StoreKit testing has it. Its price can be edited to test a real sale purchase locally.

## Risks / Trade-offs

- **[App Review must approve the new IAP before it can sell]**
  - Submit it with the next build, 2.0 (2), which contains this code.
  - Until it's approved the product doesn't load, so the sale is simply off. That fails safe.
- **[Per-storefront prices could invert]** If a territory's sale price were set manually equal to or above the normal price, that storefront shows no sale. Decision 2 handles this, so it is correct, never a "SALE" at a higher price.
- **[Reference-price rules (EU Omnibus: the struck price must be the lowest price in the prior 30 days)]**
  - The struck price is the real lifetime price users actually paid, so a one-off sale complies.
  - Back-to-back sales would not. A note goes in the guide: leave 30+ days at the normal price between sales.
- **[Two lifetime products in a user's purchase history]** Harmless, since both grant the same thing. Restore handles either.
- **[`ViewThatFits` picks by ideal size, so a long title could force layout 3 early]** Acceptable: layout 3 is fully legible, just taller. Previews at AX sizes guard it.

## Migration Plan

1. Ship the code with the sale product idle (priced equal to normal). Behaviour is identical to today until a price is scheduled.
2. **App Store Connect, with explicit OK:**
   - Create `markepi.pro.lifetime.sale` with a display name, description and review screenshot.
   - Set its base price to $4.99.
   - Attach it to the 2.0 (2) submission.
3. **Start the sale:** schedule $1.99 from Oct 6 to Oct 31. The scheduled end returns it to $4.99, which ends the sale automatically.
4. **Rollback:** set the sale product's price back to $4.99. No app update needed.
