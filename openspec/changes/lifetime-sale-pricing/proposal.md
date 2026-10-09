## Why

Markepi has no way to run a sale. Changing the lifetime price in App Store Connect just shows a new number, so nobody can tell it is a discount. The planned r/AppHookup sale (Lifetime $4.99 → $1.99, Oct 6–31) needs the paywall to show the old price struck through, the new price, and a SALE tag. The home screen should also announce the sale, as AutoAlign does.

## What Changes

- **New product: a sale lifetime unlock.** A second non-consumable, `markepi.pro.lifetime.sale`, grants the same Pro entitlement as `markepi.pro.lifetime`. The sale is controlled only by its App Store Connect price, with no app update:
  - **Sale price equals the normal lifetime price:** no sale. The paywall shows and sells the normal lifetime product exactly as today.
  - **Sale price is lower:** the sale is on. The lifetime card strikes through the normal price, shows the sale price with a **SALE** tag, and the purchase buys the sale product.
  - **Sale price is higher, or the product fails to load:** treated as no sale.
- **Wrapping that holds up in every currency.** The struck price, the sale price and the SALE tag sit on one line when they fit. In long currencies, at large Dynamic Type sizes, or on narrow widths, they move to a second line in a defined order instead of truncating or squeezing.
- **iPad and landscape.** The same rules apply in the iPad form sheet, the iPad full-screen onboarding paywall, and compact-height landscape. Layout follows the space actually available, not the device type.
- **Home screen sale signal.** For free users while a sale is on, the toolbar crown on the start screen becomes a capsule with the crown and a **SALE** label, like AutoAlign's premium button. Pro users never see it.
- The purchase button shows the sale price ("Unlock Forever — $1.99").
- While the sale is on, the lifetime card's "Best value" badge is hidden, so the card carries one badge: SALE.
- **Restore:** owning either lifetime product restores Pro.
- **DEBUG only:** a "Simulate Sale" toggle in Settings for testing the layout without App Store Connect.

## Capabilities

### New Capabilities
- `sale-pricing`: what counts as a sale (from the two lifetime products' prices), how the paywall shows it (struck normal price, sale price, SALE tag), the wrapping rules for long prices on iPhone, iPad and landscape, which product is purchased and restored, and the home-screen SALE signal.

### Modified Capabilities
<!-- None: the paywall and premium products have no spec yet (openspec/specs has only offline-geolocation and photo-frames). -->

## Impact

- **MarkepiCore / Premium:**
  - `PremiumProduct` gains `.lifetimeSale`.
  - `StoreManager` gains the sale state: whether a sale is on, the normal and sale display prices, and which product a lifetime purchase buys.
  - The entitlement is unchanged: owning any catalog product means Pro.
- **App:**
  - `PaywallView`: the lifetime plan card's price block and the CTA. The new price-block view lives in `PaywallView.swift`, because the project file is classic pbxproj and an existing file avoids adding a new one.
  - `ContentView`: `PremiumCrownIcon` and the DEBUG Settings toggle.
- **`Markepi.storekit`:** add the sale product so local StoreKit testing works.
- **App Store Connect (manual, needs explicit OK):**
  - Create the `markepi.pro.lifetime.sale` non-consumable.
  - Price it at $4.99 (no sale) until the sale starts.
  - Schedule $1.99 for Oct 6–31.
  - Submit it for review with the next app version.
- **Not affected:**
  - Monthly and annual subscriptions.
  - Export tiers.
  - The export comparison sheet, which keeps its "Unlock full quality" button and opens the same paywall.
